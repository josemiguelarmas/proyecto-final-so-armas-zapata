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
readonly REQUIRED_CMDS=(getent df find sort head awk du findmnt lsblk)

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

option_users() {
    print_header 'Usuarios del sistema y último inicio de sesión'
    printf 'Opción en construcción.\n'
}

# ---------------------------------------------------------------------------
# Option 2: filesystems and disks
# ---------------------------------------------------------------------------

option_filesystems() {
    print_header 'Sistemas de archivos y discos'
    printf 'Opción en construcción.\n'
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
