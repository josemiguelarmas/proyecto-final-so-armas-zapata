#!/usr/bin/env bash
#
# run-tests.sh - Runs the sysadmin-tool.sh BATS suite.
#
# Usage:
#   tests/run-tests.sh                 # all tests
#   sudo tests/run-tests.sh            # includes tests that require root
#   tests/run-tests.sh test_menu.bats  # only some files
#   tests/run-tests.sh --tap           # additional options for bats
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if ! command -v bats >/dev/null 2>&1; then
    printf 'ERROR: bats no está instalado (sudo apt install bats).\n' >&2
    exit 2
fi

opts=()
files=()
for arg in "$@"; do
    case "${arg}" in
        *.bats)
            if [[ -e "${arg}" ]]; then
                files+=("${arg}")
            else
                files+=("${TESTS_DIR}/${arg##*/}")
            fi
            ;;
        # Anything else (e.g. --tap, -f pattern) is passed to bats.
        *) opts+=("${arg}") ;;
    esac
done
if ((${#files[@]} == 0)); then
    files=("${TESTS_DIR}")
fi

printf 'Ejecutando BATS como %s (UID %d)\n' "$(id -un)" "${EUID}"
exec bats "${opts[@]}" "${files[@]}"
