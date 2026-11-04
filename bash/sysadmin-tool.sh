#!/usr/bin/env bash
#
# sysadmin-tool.sh - Interactive system administration tool for data center
# administrators. Final project, Operating Systems course, Universidad Icesi.
#
# Usage: ./sysadmin-tool.sh
#
# All user-facing text is in Spanish; code and comments are in English.

# -e is intentionally NOT used: in an interactive menu a single failing command
# must not kill the whole program. Each function checks its own errors.
set -uo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly REQUIRED_CMDS=(getent df find sort head tail tr wc awk du date mktemp basename
    sync findmnt lsblk)

# On Fedora/RHEL tools such as lastlog2 live in /usr/sbin, which is often not
# in a regular user's PATH, so these directories are searched as well.
readonly SBIN_DIRS=(/usr/sbin /sbin)

# Accounts with UID >= this value are considered human users (plus root).
readonly HUMAN_UID_MIN=1000
# "nobody" has UID 65534 (>= 1000) but is a system account, not a person.
readonly NOBODY_UID=65534

# Virtual/in-memory filesystems hidden by default in option 2: they do not
# correspond to a disk. The first four are the ones named in the requirements.
readonly PSEUDO_FS_TYPES=(tmpfs devtmpfs squashfs overlay efivarfs ramfs
    rootfs proc sysfs devpts cgroup cgroup2 autofs)

# Last-login tool detected at runtime (see detect_login_tool).
LOGIN_TOOL_NAME=''
LOGIN_TOOL_PATH=''

# State shared between the backup helpers (option 5).
USB_TARGETS=()
USB_LABELS=()
SELECTED_DEST=''
# Path typed by the user, set by read_path.
INPUT_PATH=''
COPY_METHOD=''
# Set while a backup is being written, so Ctrl+C can report it as incomplete.
CURRENT_BACKUP_DIR=''

# Temporary files registered here are removed by cleanup() on exit.
TMP_FILES=()

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

print_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

print_warning() {
    printf 'ADVERTENCIA: %s\n' "$*" >&2
}

print_header() {
    printf '\n=== %s ===\n\n' "$1"
}

# Prints "  label   value" with the label padded to 22 characters.
# printf "%-22s" pads by BYTES, so labels with accents (2 bytes in UTF-8)
# would be misaligned; ${#label} counts characters in a UTF-8 locale.
print_field() {
    local label="$1" value="$2"
    printf '  %s%*s %s\n' "${label}" $((22 - ${#label})) '' "${value}"
}

# Only clear when stdout is a terminal, so output redirected to a file or a
# test harness is not filled with escape sequences.
clear_screen() {
    # clear (ncurses) is optional: minimal containers may not include it.
    if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
        clear
    fi
}

pause() {
    local _
    printf '\n'
    read -r -p 'Presione Enter para volver al menú...' _ || true
}

is_root() {
    [[ "${EUID}" -eq 0 ]]
}

warn_if_not_root() {
    if ! is_root; then
        print_warning "$1"
    fi
}

# Reads a path typed by the user into INPUT_PATH. IFS= keeps leading and
# trailing spaces (valid in file names) and a leading "~" is expanded to
# $HOME, as the shell would do on the command line.
read_path() {
    IFS= read -r -p "$1" INPUT_PATH || return 1
    # The literal "~" typed by the user is compared on purpose.
    # shellcheck disable=SC2088
    if [[ "${INPUT_PATH}" == '~' || "${INPUT_PATH}" == '~/'* ]]; then
        INPUT_PATH="${HOME}${INPUT_PATH:1}"
    fi
}

# Asks a yes/no question; succeeds only when the answer is "s" or "S".
confirm() {
    local answer
    read -r -p "$1" answer || return 1
    if [[ "${answer}" =~ ^[sS]$ ]]; then
        return 0
    fi
    printf 'Operación cancelada.\n'
    return 1
}

# Formats a byte count in human-readable IEC units (KiB, MiB, ...).
# numfmt (GNU coreutils) is preferred; awk is the portable fallback.
human_size() {
    local bytes="$1"
    if ((bytes < 1024)); then
        printf '%sB\n' "${bytes}"
    elif command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B --format='%.1f' "${bytes}"
    else
        awk -v b="${bytes}" 'BEGIN {
            split("B KiB MiB GiB TiB PiB", u, " ")
            i = 1
            while (b >= 1024 && i < 6) { b /= 1024; i++ }
            printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i]
        }'
    fi
}

# Percentage with two decimals; prints 0.00 when the total is zero.
percentage() {
    local part="$1" total="$2"
    awk -v p="${part}" -v t="${total}" \
        'BEGIN { if (t == 0) print "0.00"; else printf "%.2f\n", (p * 100) / t }'
}

# ---------------------------------------------------------------------------
# Startup checks
# ---------------------------------------------------------------------------

check_dependencies() {
    local cmd missing=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    if ((${#missing[@]} > 0)); then
        print_error "${SCRIPT_NAME}: faltan comandos obligatorios: ${missing[*]}"
        print_error "instálelos (paquetes coreutils, findutils, gawk/mawk, util-linux, libc-bin/glibc-common) y vuelva a ejecutar."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Option 1: users and last login
# ---------------------------------------------------------------------------

# Prints the full path of a command, looking in PATH and then in SBIN_DIRS.
find_command() {
    local name="$1" dir
    if command -v "${name}" >/dev/null 2>&1; then
        command -v "${name}"
        return 0
    fi
    for dir in "${SBIN_DIRS[@]}"; do
        if [[ -x "${dir}/${name}" ]]; then
            printf '%s\n' "${dir}/${name}"
            return 0
        fi
    done
    return 1
}

# Picks the first available last-login tool. The order reflects current
# distributions: lastlog2 (util-linux, Debian 13+/Ubuntu 25.04+/Fedora),
# lastlog (shadow-utils, RHEL 9 and older releases), last (wtmp, everywhere).
detect_login_tool() {
    local tool path
    for tool in lastlog2 lastlog last; do
        if path="$(find_command "${tool}")"; then
            LOGIN_TOOL_NAME="${tool}"
            LOGIN_TOOL_PATH="${path}"
            return 0
        fi
    done
    return 1
}

# Reads one user's record from lastlog or lastlog2. Both print the layout:
#   Username   Port   From        Latest
#   alice      pts/0  10.0.0.5    Tue Nov  3 16:08:53 +0000 2026
#   bob                           **Never logged in**
# Port and From can be empty, so the timestamp is taken as the LAST five
# fields instead of a fixed column number.
# Prints "YYYY-MM-DD HH:MM:SS", "NEVER" or "UNAVAILABLE".
login_from_lastlog() {
    local user="$1" line timestamp
    line="$(LC_ALL=C "${LOGIN_TOOL_PATH}" -u "${user}" 2>/dev/null | awk 'NR == 2')"
    if [[ -z "${line}" ]]; then
        printf 'UNAVAILABLE\n'
    elif [[ "${line}" == *'**Never logged in**'* ]]; then
        printf 'NEVER\n'
    else
        timestamp="$(awk '{ print $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF }' <<<"${line}")"
        LC_ALL=C date -d "${timestamp}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
            printf 'UNAVAILABLE\n'
    fi
}

# Reads one user's most recent session from wtmp using "last". The ISO time
# format (2026-11-03T16:07:37-05:00) is unambiguous and easy to split.
# Prints "YYYY-MM-DD HH:MM:SS", "NEVER" or "UNAVAILABLE".
login_from_last() {
    local user="$1" output field
    local -a fields
    if ! output="$(LC_ALL=C "${LOGIN_TOOL_PATH}" --time-format iso -n 1 "${user}" 2>/dev/null)"; then
        printf 'UNAVAILABLE\n'
        return
    fi
    # The first line is the user's latest session; when there is none, last
    # only prints a blank line and "wtmp begins ...".
    read -r -a fields <<<"$(head -n 1 <<<"${output}")"
    for field in "${fields[@]}"; do
        if [[ "${field}" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            return
        fi
    done
    printf 'NEVER\n'
}

get_last_login() {
    local user="$1"
    case "${LOGIN_TOOL_NAME}" in
        lastlog2 | lastlog) login_from_lastlog "${user}" ;;
        last) login_from_last "${user}" ;;
        *) printf 'UNAVAILABLE\n' ;;
    esac
}

is_human_uid() {
    local uid="$1"
    ((uid == 0 || (uid >= HUMAN_UID_MIN && uid != NOBODY_UID)))
}

# Prints a table of accounts. Arguments: section title, then a list of
# "username:uid" entries.
print_users_table() {
    local title="$1" entry user uid login date time
    shift
    printf '%s (%d)\n' "${title}" "$#"
    printf '%-24s %8s  %-10s %-8s\n' 'USUARIO' 'UID' 'FECHA' 'HORA'
    printf '%-24s %8s  %-10s %-8s\n' '-------' '---' '-----' '----'
    for entry in "$@"; do
        user="${entry%%:*}"
        uid="${entry##*:}"
        login="$(get_last_login "${user}")"
        case "${login}" in
            NEVER) printf '%-24s %8s  %s\n' "${user}" "${uid}" 'Nunca ha iniciado sesión' ;;
            UNAVAILABLE) printf '%-24s %8s  %s\n' "${user}" "${uid}" 'No disponible' ;;
            *)
                date="${login%% *}"
                time="${login##* }"
                printf '%-24s %8s  %-10s %-8s\n' "${user}" "${uid}" "${date}" "${time}"
                ;;
        esac
    done
    printf '\n'
}

option_users() {
    local choice user uid
    local -a humans=() system=()

    print_header 'Usuarios del sistema y último inicio de sesión'
    printf '  1) Solo usuarios humanos (root y UID >= %d)\n' "${HUMAN_UID_MIN}"
    printf '  2) Todas las cuentas (humanas y de sistema)\n'
    read -r -p 'Seleccione: ' choice || return 1
    if [[ "${choice}" != '1' && "${choice}" != '2' ]]; then
        print_error "opción no válida: '${choice}'."
        return 1
    fi

    if detect_login_tool; then
        printf '\nFuente del último inicio de sesión: %s\n\n' "${LOGIN_TOOL_PATH}"
    else
        print_warning 'no se encontró lastlog2, lastlog ni last; no se puede obtener el último inicio de sesión.'
        print_warning 'instale el paquete "lastlog2" (Debian/Ubuntu) o "util-linux" (Fedora/RHEL).'
        printf '\n'
    fi

    # getent (instead of reading /etc/passwd) also returns accounts from
    # LDAP/NIS/SSSD when the system is configured to use them.
    while IFS=: read -r user _ uid _; do
        if is_human_uid "${uid}"; then
            humans+=("${user}:${uid}")
        else
            system+=("${user}:${uid}")
        fi
    done < <(getent passwd)

    print_users_table 'USUARIOS HUMANOS' "${humans[@]}"
    if [[ "${choice}" == '2' ]]; then
        print_users_table 'CUENTAS DE SISTEMA' "${system[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Option 2: filesystems and disks
# ---------------------------------------------------------------------------

# Returns the length of the longest argument (used to size table columns).
max_length() {
    local item max=0
    for item in "$@"; do
        if ((${#item} > max)); then
            max=${#item}
        fi
    done
    printf '%d\n' "${max}"
}

option_filesystems() {
    local choice fs source fstype size avail target i
    local w_src w_type w_target
    local -a df_args=(-B1 '--output=source,fstype,size,avail,target')
    local -a sources=() types=() sizes=() avails=() targets=()

    print_header 'Sistemas de archivos y discos'
    read -r -p '¿Incluir pseudo-sistemas de archivos (tmpfs, overlay, ...)? [s/N]: ' choice || return 1
    if [[ ! "${choice}" =~ ^[sS]$ ]]; then
        for fs in "${PSEUDO_FS_TYPES[@]}"; do
            df_args+=(-x "${fs}")
        done
    fi

    # "read" assigns everything left on the line to the last variable, so a
    # mount point containing spaces is kept intact in "target".
    while read -r source fstype size avail target; do
        sources+=("${source}")
        types+=("${fstype}")
        sizes+=("${size}")
        avails+=("${avail}")
        targets+=("${target}")
    done < <(LC_ALL=C df "${df_args[@]}" 2>/dev/null | tail -n +2)

    if ((${#sources[@]} == 0)); then
        print_error 'df no devolvió ningún sistema de archivos.'
        return 1
    fi

    # Column widths adapt to the data so the table stays aligned.
    w_src="$(max_length 'DISPOSITIVO' "${sources[@]}")"
    w_type="$(max_length 'TIPO' "${types[@]}")"
    w_target="$(max_length 'MONTAJE' "${targets[@]}")"

    printf "%-${w_src}s  %-${w_type}s  %18s  %18s  %s\n" \
        'DISPOSITIVO' 'TIPO' 'TOTAL (BYTES)' 'DISPONIBLE (BYTES)' 'MONTAJE'
    printf '%*s\n' $((w_src + w_type + w_target + 44)) '' | tr ' ' '-'
    for i in "${!sources[@]}"; do
        printf "%-${w_src}s  %-${w_type}s  %18s  %18s  %s\n" \
            "${sources[i]}" "${types[i]}" "${sizes[i]}" "${avails[i]}" "${targets[i]}"
    done

    # Complementary view of the physical block devices (loop devices, major
    # number 7, are excluded because they are usually snap/squashfs images).
    printf '\nDiscos físicos (lsblk -b):\n'
    lsblk -b -d -e 1,7 -o NAME,TYPE,SIZE,RM,TRAN,MODEL 2>/dev/null ||
        print_warning 'no se pudo obtener la información de lsblk.'
}

# ---------------------------------------------------------------------------
# Option 3: ten largest files
# ---------------------------------------------------------------------------

# Turns the user's input into an absolute directory to search. A block device
# is translated to its mount point with findmnt (the first one if the device
# is mounted in several places).
resolve_search_path() {
    local input="$1" mount_point
    if [[ -b "${input}" ]]; then
        mount_point="$(findmnt -n -f -o TARGET --source "${input}" 2>/dev/null)"
        if [[ -z "${mount_point}" ]]; then
            print_error "el dispositivo '${input}' no está montado; móntelo antes de buscar."
            return 1
        fi
        printf '%s\n' "${mount_point}"
    elif [[ -d "${input}" ]]; then
        # pwd -P gives the absolute physical path, so find prints absolute
        # paths even if the user typed a relative one or a symlink.
        if ! (cd -P -- "${input}" 2>/dev/null && pwd -P); then
            print_error "no hay permiso para acceder a '${input}'."
            return 1
        fi
    elif [[ -e "${input}" ]]; then
        print_error "'${input}' no es un directorio ni un dispositivo de bloques."
        return 1
    else
        print_error "'${input}' no existe."
        return 1
    fi
}

option_largest_files() {
    local input search_path fs_mount err_file record size file rank=0 errors

    print_header 'Los diez archivos más grandes'
    read_path 'Ingrese un dispositivo (ej. /dev/sdb1) o punto de montaje (ej. /home): ' || return 1
    input="${INPUT_PATH}"
    if [[ -z "${input}" ]]; then
        print_error 'no se ingresó ninguna ruta.'
        return 1
    fi
    search_path="$(resolve_search_path "${input}")" || return 1
    fs_mount="$(findmnt -n -o TARGET -T "${search_path}" 2>/dev/null)"

    printf '\nBuscando en: %s\n' "${search_path}"
    if [[ -n "${fs_mount}" && "${fs_mount}" != "${search_path}" ]]; then
        printf 'Nota: no es un punto de montaje; pertenece al sistema de archivos montado en %s.\n' "${fs_mount}"
        printf 'Se busca solo dentro de esta ruta, sin salir de ese sistema de archivos.\n'
    fi
    warn_if_not_root 'sin privilegios de root algunos directorios pueden no ser accesibles.'
    printf 'Esto puede tardar en sistemas de archivos grandes...\n\n'

    # mktemp runs in the current shell (not in $(...) of a helper) so the
    # file is registered in TMP_FILES and removed by cleanup() on exit.
    err_file="$(mktemp)" || return 1
    TMP_FILES+=("${err_file}")

    printf '%3s  %16s  %10s  %s\n' '#' 'BYTES' 'LEGIBLE' 'RUTA'
    # -xdev: do not descend into other filesystems mounted below the path.
    # Records are "size<TAB>path" terminated by NUL, so names with spaces or
    # even newlines survive sort and head (-z) and read -d ''.
    # sort cannot output anything until find has finished, so err_file is
    # complete by the time the loop ends.
    # The record is split by hand at the FIRST tab: "IFS=$'\t' read size file"
    # would strip a tab at the end of a file name.
    while IFS= read -r -d '' record; do
        size="${record%%$'\t'*}"
        file="${record#*$'\t'}"
        rank=$((rank + 1))
        # A newline inside a name would break the table; show it as "\n".
        printf '%3d  %16s  %10s  %s\n' "${rank}" "${size}" "$(human_size "${size}")" "${file//$'\n'/\\n}"
    done < <(LC_ALL=C find "${search_path}" -xdev -type f -printf '%s\t%p\0' 2>"${err_file}" |
        sort -z -rn | head -z -n 10)

    if ((rank == 0)); then
        printf 'No se encontraron archivos regulares en %s.\n' "${search_path}"
    fi

    errors="$(wc -l <"${err_file}")"
    if ((errors > 0)); then
        printf '\n'
        print_warning "find no pudo leer ${errors} ruta(s) (permisos u otros errores); los resultados pueden estar incompletos."
    fi
}

# ---------------------------------------------------------------------------
# Option 4: RAM and swap
# ---------------------------------------------------------------------------

# Prints one "label: bytes (human) percent" line of the memory report.
print_memory_line() {
    local label="$1" bytes="$2" percent="${3:-}"
    printf '  %-27s %16s bytes  %10s' "${label}" "${bytes}" "$(human_size "${bytes}")"
    if [[ -n "${percent}" ]]; then
        printf '  %6s %%' "${percent}"
    fi
    printf '\n'
}

option_memory() {
    local mem_total mem_free mem_avail swap_total swap_free swap_used estimated

    print_header 'Memoria RAM y swap'
    if [[ ! -r /proc/meminfo ]]; then
        print_error 'no se puede leer /proc/meminfo.'
        return 1
    fi

    # /proc/meminfo labels values as "kB" but they are KiB, hence * 1024.
    # printf "%.0f" avoids awk printing large numbers in scientific notation.
    # MemAvailable exists since Linux 3.14; on older kernels it is estimated
    # as MemFree + Buffers + Cached (estimated=1).
    read -r mem_total mem_free mem_avail swap_total swap_free estimated < <(awk '
        /^MemTotal:/     { total = $2 }
        /^MemFree:/      { free = $2 }
        /^MemAvailable:/ { avail = $2; has_avail = 1 }
        /^Buffers:/      { buffers = $2 }
        /^Cached:/       { cached = $2 }
        /^SwapTotal:/    { swap_total = $2 }
        /^SwapFree:/     { swap_free = $2 }
        END {
            if (!has_avail) avail = free + buffers + cached
            printf "%.0f %.0f %.0f %.0f %.0f %d\n", total * 1024, free * 1024,
                avail * 1024, swap_total * 1024, swap_free * 1024, !has_avail
        }' /proc/meminfo)

    if [[ -z "${mem_total}" || "${mem_total}" -eq 0 ]]; then
        print_error 'no se pudo interpretar /proc/meminfo.'
        return 1
    fi

    printf 'Memoria RAM (fuente: /proc/meminfo)\n'
    print_memory_line 'Total (MemTotal):' "${mem_total}"
    print_memory_line 'Libre (MemFree):' "${mem_free}" "$(percentage "${mem_free}" "${mem_total}")"
    print_memory_line 'Disponible (MemAvailable):' "${mem_avail}" "$(percentage "${mem_avail}" "${mem_total}")"
    if [[ "${estimated}" == '1' ]]; then
        print_warning 'el kernel no expone MemAvailable; se estimó como MemFree + Buffers + Cached.'
    fi
    printf '  (Libre = memoria sin usar; Disponible = memoria utilizable sin recurrir a swap,\n'
    printf '   incluye cachés que el kernel puede liberar.)\n\n'

    printf 'Swap\n'
    # Guard against division by zero: systems without swap report 0.
    if ((swap_total == 0)); then
        print_memory_line 'Total (SwapTotal):' 0
        printf '  No hay swap configurada; el uso es 0 bytes y el porcentaje no aplica.\n'
        return 0
    fi
    swap_used=$((swap_total - swap_free))
    print_memory_line 'Total (SwapTotal):' "${swap_total}"
    print_memory_line 'Usada (Total - Free):' "${swap_used}" "$(percentage "${swap_used}" "${swap_total}")"
}

# ---------------------------------------------------------------------------
# Option 5: backup to USB
# ---------------------------------------------------------------------------

# Fills USB_TARGETS and USB_LABELS with the mount points of removable disks.
# A disk counts as removable when its transport is USB or the kernel marks it
# as removable (RM) or hot-pluggable (HOTPLUG): many USB SSDs report RM=0.
find_usb_mount_points() {
    local disk type rm hotplug tran part size target
    USB_TARGETS=()
    USB_LABELS=()
    # -d whole disks only, -n no header, -p full paths, -r one space between
    # fields. TRAN goes last because it is empty for non-USB disks.
    while read -r disk type rm hotplug tran; do
        if [[ "${type}" != 'disk' ]]; then
            continue
        fi
        if [[ "${tran}" != 'usb' && "${rm}" != '1' && "${hotplug}" != '1' ]]; then
            continue
        fi
        # The disk itself and its partitions; each can have several mounts.
        while read -r part size; do
            while IFS= read -r target; do
                if [[ -n "${target}" ]]; then
                    USB_TARGETS+=("${target}")
                    USB_LABELS+=("${part} (${size}) montado en ${target}")
                fi
            done < <(findmnt -n -o TARGET --source "${part}" 2>/dev/null)
        done < <(lsblk -npr -o NAME,SIZE "${disk}" 2>/dev/null)
    done < <(lsblk -dnpr -o NAME,TYPE,RM,HOTPLUG,TRAN 2>/dev/null)
}

# Shows the detected USB mount points and lets the user pick one or type a
# path manually (needed in WSL/VMs without USB passthrough).
# Sets SELECTED_DEST; returns 1 when the user cancels or the input is invalid.
select_destination() {
    local choice i
    SELECTED_DEST=''

    printf '\nDispositivos de bloque (lsblk -o NAME,RM,TRAN,SIZE,MOUNTPOINT):\n'
    lsblk -e 1,7 -o NAME,RM,TRAN,SIZE,MOUNTPOINT 2>/dev/null ||
        print_warning 'no se pudo ejecutar lsblk.'

    find_usb_mount_points
    printf '\nDestinos disponibles:\n'
    if ((${#USB_TARGETS[@]} == 0)); then
        printf '  (no se detectaron memorias USB montadas)\n'
    fi
    for i in "${!USB_LABELS[@]}"; do
        printf '  %d) %s\n' $((i + 1)) "${USB_LABELS[i]}"
    done
    printf '  m) Ingresar una ruta de destino manualmente\n'
    printf '  c) Cancelar\n'
    read -r -p 'Seleccione el destino: ' choice || return 1

    if [[ "${choice}" == 'm' || "${choice}" == 'M' ]]; then
        read_path 'Ruta de destino: ' || return 1
        SELECTED_DEST="${INPUT_PATH}"
    elif [[ "${choice}" =~ ^[0-9]+$ ]] && ((10#${choice} >= 1 && 10#${choice} <= ${#USB_TARGETS[@]})); then
        SELECTED_DEST="${USB_TARGETS[10#${choice} - 1]}"
    elif [[ "${choice}" == 'c' || "${choice}" == 'C' ]]; then
        printf 'Operación cancelada.\n'
        return 1
    else
        print_error "opción de destino no válida: '${choice}'."
        return 1
    fi
    if [[ -z "${SELECTED_DEST}" ]]; then
        print_error 'no se ingresó ninguna ruta de destino.'
        return 1
    fi
}

# Prints the absolute physical path of a directory.
absolute_dir() {
    (cd -P -- "$1" 2>/dev/null && pwd -P)
}

validate_backup_source() {
    local src="$1"
    if [[ ! -e "${src}" ]]; then
        print_error "el directorio de origen '${src}' no existe."
    elif [[ ! -d "${src}" ]]; then
        print_error "'${src}' no es un directorio."
    elif [[ ! -r "${src}" || ! -x "${src}" ]]; then
        print_error "no tiene permiso de lectura sobre '${src}'."
    else
        return 0
    fi
    return 1
}

# Arguments: absolute source, absolute destination.
validate_backup_destination() {
    local src="$1" dest="$2" mount_point
    mount_point="$(findmnt -n -o TARGET -T "${dest}" 2>/dev/null)"
    if [[ -z "${mount_point}" ]]; then
        print_error "'${dest}' no pertenece a ningún sistema de archivos montado."
        return 1
    fi
    # access(W_OK) also fails on filesystems mounted read-only (EROFS).
    if [[ ! -w "${dest}" ]]; then
        print_error "no tiene permiso de escritura en '${dest}' (o está montado como solo lectura)."
        return 1
    fi
    # Copying a directory into itself would recurse forever. The trailing
    # "/" avoids treating /home/ana2 as being inside /home/ana.
    if [[ "${dest}/" == "${src%/}/"* ]]; then
        print_error 'el destino no puede estar dentro del directorio de origen.'
        return 1
    fi
    if [[ "$(findmnt -n -o TARGET -T "${src}" 2>/dev/null)" == "${mount_point}" ]]; then
        print_warning 'el destino está en el mismo sistema de archivos que el origen; la copia no protege ante una falla de ese disco.'
    fi
    return 0
}

# Arguments: required bytes, absolute destination.
check_free_space() {
    local required="$1" dest="$2" available
    available="$(df -B1 --output=avail -- "${dest}" 2>/dev/null | tail -n 1 | tr -d ' ')"
    if [[ ! "${available}" =~ ^[0-9]+$ ]]; then
        print_error "no se pudo determinar el espacio libre en '${dest}'."
        return 1
    fi
    printf 'Espacio requerido (du -sb): %s bytes (%s)\n' "${required}" "$(human_size "${required}")"
    printf 'Espacio disponible:         %s bytes (%s)\n' "${available}" "$(human_size "${available}")"
    if ((required >= available)); then
        print_error 'espacio insuficiente en el destino.'
        return 1
    fi
}

# FAT filesystems (typical on USB drives) cannot store Unix owners,
# permissions or symlinks, and keep timestamps with 2-second precision.
is_fat_filesystem() {
    case "$1" in
        vfat | msdos | fat | exfat) return 0 ;;
        *) return 1 ;;
    esac
}

# Copies the CONTENTS of src into dst. Prints the method used.
# Returns 0 on success, 1 on a partial or failed copy.
# Arguments: source, destination directory, destination filesystem type.
copy_tree() {
    local src="$1" dst="$2" fstype="$3" rc
    local -a rsync_opts=(-a)
    if is_fat_filesystem "${fstype}"; then
        # -r recursive, -t keep times; no owner/permission/symlink copies.
        rsync_opts=(-rt --modify-window=2)
    fi

    if command -v rsync >/dev/null 2>&1; then
        COPY_METHOD="rsync ${rsync_opts[*]}"
        # The trailing "/" on the source copies its contents, not the folder.
        rsync "${rsync_opts[@]}" -- "${src}/" "${dst}/"
        rc=$?
    else
        COPY_METHOD='cp -a'
        if is_fat_filesystem "${fstype}"; then
            COPY_METHOD='cp -r --preserve=timestamps'
            cp -r --preserve=timestamps -- "${src}/." "${dst}/"
        else
            cp -a -- "${src}/." "${dst}/"
        fi
        rc=$?
    fi
    if ((rc != 0)); then
        print_warning "la copia terminó con errores (código ${rc}); algunos archivos pueden no haberse copiado."
        return 1
    fi
    return 0
}

# Writes catalogo.txt: relative path and last modification date/time of every
# file and directory in the source.
write_catalog() {
    local src="$1" catalog="$2"
    {
        printf '# Catálogo de la copia de seguridad de: %s\n' "${src}"
        printf '# Generado: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '# ruta_relativa\tfecha_hora_modificacion\n'
        # %P = path relative to the starting point; %T = modification time.
        # Records end in NUL so a name containing a newline stays one record;
        # after sorting, tr shows such newlines as "?" and turns NUL into the
        # line terminator.
        # "|| true": find exits 1 when it meets an unreadable directory even
        # though the catalog is written; only a failing redirection (e.g. a
        # full or read-only disk) must count as an error.
        find "${src}" -mindepth 1 -printf '%P\t%TY-%Tm-%Td %TH:%TM:%TS\0' 2>/dev/null |
            LC_ALL=C sort -z | tr '\n\0' '?\n' || true
    } >"${catalog}"
}

# Two backups started in the same second would get the same name and be
# merged; a numeric suffix keeps every backup in its own folder.
unique_backup_dir() {
    local candidate="$1" n=1
    while [[ -e "${candidate}" ]]; do
        candidate="$1_${n}"
        n=$((n + 1))
    done
    printf '%s\n' "${candidate}"
}

# Prints "<number of regular files> <sum of their sizes in bytes>".
# Regular files are compared instead of "du -sb" because directory sizes
# differ between filesystems (ext4 vs vfat) and between du implementations.
tree_stats() {
    local dir="$1" count bytes
    count="$(find "${dir}" -type f -printf '.' 2>/dev/null | wc -c)"
    bytes="$(find "${dir}" -type f -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { printf "%.0f\n", s }')"
    printf '%s %s\n' "${count}" "${bytes}"
}

# Interactive part of option 5: asks for source and destination and runs
# every validation before anything is written.
option_backup() {
    local src_abs dest_abs mount_point fstype required base backup_dir

    print_header 'Copia de seguridad a memoria USB'
    warn_if_not_root 'sin privilegios de root los archivos no legibles por su usuario no se copiarán.'

    read_path 'Directorio a respaldar: ' || return 1
    validate_backup_source "${INPUT_PATH}" || return 1
    src_abs="$(absolute_dir "${INPUT_PATH}")" || return 1

    select_destination || return 1
    if [[ ! -d "${SELECTED_DEST}" ]]; then
        print_error "el destino '${SELECTED_DEST}' no existe o no es un directorio."
        return 1
    fi
    dest_abs="$(absolute_dir "${SELECTED_DEST}")" || return 1
    validate_backup_destination "${src_abs}" "${dest_abs}" || return 1

    # findmnt -T always finds at least "/", so a destination on the root
    # filesystem usually means the USB drive is NOT mounted there (e.g. an
    # empty /media/usb folder). The user must confirm explicitly.
    mount_point="$(findmnt -n -o TARGET -T "${dest_abs}" 2>/dev/null)"
    if [[ "${mount_point}" == '/' ]]; then
        print_warning "el destino está en el sistema de archivos raíz (/), no en un dispositivo montado aparte."
        confirm '¿Seguro que desea usar este destino? [s/N]: ' || return 1
    fi
    fstype="$(findmnt -n -o FSTYPE -T "${dest_abs}" 2>/dev/null)"

    printf '\nCalculando el tamaño del origen...\n'
    required="$(du -sb -- "${src_abs}" 2>/dev/null | awk '{ print $1 }')"
    if [[ ! "${required}" =~ ^[0-9]+$ ]]; then
        print_error "no se pudo calcular el tamaño de '${src_abs}'."
        return 1
    fi
    check_free_space "${required}" "${dest_abs}" || return 1

    # The source can never be "/" here: every destination would be inside it.
    base="$(basename -- "${src_abs}")"
    backup_dir="$(unique_backup_dir "${dest_abs}/backup_${base}_$(date '+%Y%m%d_%H%M%S')")"

    printf '\nOrigen:  %s\nDestino: %s (sistema de archivos: %s)\n' "${src_abs}" "${backup_dir}" "${fstype:-desconocido}"
    if is_fat_filesystem "${fstype}"; then
        print_warning 'destino FAT: no se conservan propietarios, permisos ni enlaces simbólicos.'
    fi
    confirm '¿Iniciar la copia? [s/N]: ' || return 1

    run_backup "${src_abs}" "${backup_dir}" "${backup_dir}/${base}" "${fstype}"
}

# Copies, writes the catalog, verifies and syncs.
# Arguments: absolute source, backup folder, copy folder, destination fstype.
run_backup() {
    local src_abs="$1" backup_dir="$2" copy_dir="$3" fstype="$4"
    local src_count src_bytes dst_count dst_bytes copy_ok=1 verified=0
    local start_time end_time result

    if ! mkdir -- "${backup_dir}" || ! mkdir -- "${copy_dir}"; then
        print_error "no se pudo crear '${copy_dir}'."
        return 1
    fi
    CURRENT_BACKUP_DIR="${backup_dir}"
    start_time="$(date +%s)"

    printf '\nCopiando archivos...\n'
    copy_tree "${src_abs}" "${copy_dir}" "${fstype}" || copy_ok=0
    printf 'Generando catalogo.txt...\n'
    if ! write_catalog "${src_abs}" "${backup_dir}/catalogo.txt"; then
        print_warning 'no se pudo escribir catalogo.txt.'
    fi

    printf 'Verificando la copia...\n'
    read -r src_count src_bytes < <(tree_stats "${src_abs}")
    read -r dst_count dst_bytes < <(tree_stats "${copy_dir}")
    if [[ "${src_count}" == "${dst_count}" && "${src_bytes}" == "${dst_bytes}" ]]; then
        verified=1
    fi

    printf 'Sincronizando discos (sync)...\n'
    sync
    end_time="$(date +%s)"
    CURRENT_BACKUP_DIR=''

    if ((verified == 1 && copy_ok == 1)); then
        result='EXITOSA (cantidad y tamaño total coinciden)'
    else
        result='FALLIDA (la copia está incompleta o difiere del origen)'
    fi
    print_backup_summary "${src_abs}" "${backup_dir}" "${copy_dir}" \
        $((end_time - start_time)) "${src_count}" "${dst_count}" \
        "${src_bytes}" "${dst_bytes}" "${result}"
}

# Arguments: source, backup folder, copy folder, seconds, source file count,
# copy file count, source bytes, copy bytes, verification result text.
print_backup_summary() {
    local src_abs="$1" backup_dir="$2" copy_dir="$3" seconds="$4"
    local src_count="$5" dst_count="$6" src_bytes="$7" dst_bytes="$8" result="$9"

    print_header 'Resumen de la copia de seguridad'
    print_field 'Origen:' "${src_abs}"
    print_field 'Carpeta de respaldo:' "${backup_dir}"
    print_field 'Copia de archivos:' "${copy_dir}"
    print_field 'Catálogo:' "${backup_dir}/catalogo.txt"
    print_field 'Método:' "${COPY_METHOD}"
    print_field 'Duración:' "${seconds} s"
    print_field 'Archivos regulares:' "origen ${src_count} / copia ${dst_count}"
    print_field 'Bytes en archivos:' "origen ${src_bytes} / copia ${dst_bytes}"
    print_field 'Verificación:' "${result}"
    printf '\nEl dispositivo NO fue desmontado. Para retirarlo con seguridad ejecute:\n'
    printf '  umount "%s"\n' "$(findmnt -n -o TARGET -T "${backup_dir}" 2>/dev/null)"
}

# ---------------------------------------------------------------------------
# Menu and entry point
# ---------------------------------------------------------------------------

# Invoked indirectly through trap, which ShellCheck cannot follow.
# shellcheck disable=SC2329
cleanup() {
    if ((${#TMP_FILES[@]} > 0)); then
        rm -f -- "${TMP_FILES[@]}"
    fi
}

# shellcheck disable=SC2329
# Argument: exit status, 128 + signal number by shell convention
# (130 = SIGINT/Ctrl+C, 143 = SIGTERM).
on_interrupt() {
    printf '\n\nInterrupción recibida (señal). Saliendo...\n'
    if [[ -n "${CURRENT_BACKUP_DIR}" ]]; then
        print_warning "la copia de seguridad quedó INCOMPLETA en: ${CURRENT_BACKUP_DIR}"
    fi
    exit "$1"
}

show_menu() {
    printf '\n========================================\n'
    printf '  Herramienta de administración - %s\n' "$(hostname 2>/dev/null || printf 'Linux')"
    printf '========================================\n'
    printf '  1) Usuarios y último inicio de sesión\n'
    printf '  2) Sistemas de archivos y discos\n'
    printf '  3) Los diez archivos más grandes\n'
    printf '  4) Memoria RAM y swap\n'
    printf '  5) Copia de seguridad a USB\n'
    printf '  0) Salir\n'
    printf '========================================\n'
}

main() {
    local choice

    trap cleanup EXIT
    trap 'on_interrupt 130' INT
    trap 'on_interrupt 143' TERM

    check_dependencies || exit 1
    warn_if_not_root "no se está ejecutando como root; algunas opciones pueden mostrar información incompleta."

    while true; do
        clear_screen
        show_menu
        # EOF on stdin (e.g. piped input ended) must end the loop instead of
        # spinning forever on an empty choice.
        if ! read -r -p 'Seleccione una opción: ' choice; then
            printf '\n'
            break
        fi
        case "${choice}" in
            1) option_users ;;
            2) option_filesystems ;;
            3) option_largest_files ;;
            4) option_memory ;;
            5) option_backup ;;
            0)
                printf 'Hasta luego.\n'
                break
                ;;
            *) print_error "opción no válida: '${choice}'. Ingrese un número entre 0 y 5." ;;
        esac
        pause
    done
    exit 0
}

# Run the menu only when executed directly; when the file is sourced (e.g. by
# the BATS tests) just the functions are loaded.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
