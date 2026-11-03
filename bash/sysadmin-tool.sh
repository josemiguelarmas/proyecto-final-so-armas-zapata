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
readonly REQUIRED_CMDS=(getent df find sort head awk du findmnt lsblk date)

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

# Only clear when stdout is a terminal, so output redirected to a file or a
# test harness is not filled with escape sequences.
clear_screen() {
    if [[ -t 1 ]]; then
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

# Creates a temporary file, registers it for cleanup and prints its path.
make_temp_file() {
    local tmp
    tmp="$(mktemp)" || return 1
    TMP_FILES+=("${tmp}")
    printf '%s\n' "${tmp}"
}

# Formats a byte count in human-readable IEC units (KiB, MiB, ...).
# numfmt (GNU coreutils) is preferred; awk is the portable fallback.
human_size() {
    local bytes="$1"
    if command -v numfmt >/dev/null 2>&1; then
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
    local -a df_args=(-B1 --output=source,fstype,size,avail,target)
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
    lsblk -b -d -e 7 -o NAME,TYPE,SIZE,RM,TRAN,MODEL 2>/dev/null ||
        print_warning 'no se pudo obtener la información de lsblk.'
}

# ---------------------------------------------------------------------------
# Option 3: ten largest files
# ---------------------------------------------------------------------------

option_largest_files() {
    print_header 'Los diez archivos más grandes'
    printf 'Opción en construcción.\n'
}

# ---------------------------------------------------------------------------
# Option 4: RAM and swap
# ---------------------------------------------------------------------------

option_memory() {
    print_header 'Memoria RAM y swap'
    printf 'Opción en construcción.\n'
}

# ---------------------------------------------------------------------------
# Option 5: backup to USB
# ---------------------------------------------------------------------------

option_backup() {
    print_header 'Copia de seguridad a memoria USB'
    printf 'Opción en construcción.\n'
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
on_interrupt() {
    printf '\n\nInterrupción recibida (Ctrl+C). Saliendo...\n'
    # Exit status 130 = 128 + SIGINT, the shell convention.
    exit 130
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
    trap on_interrupt INT TERM

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

main "$@"
