# shellcheck shell=bash
#
# test_helper.bash - Functions shared by all BATS suites.
#
# Usage in a .bats file:
#     load test_helper
#
# Meant to be reused in future suites (e.g. test_option5_backup.bats).

# run --separate-stderr needs BATS >= 1.5.0.
bats_require_minimum_version 1.5.0

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." && pwd -P)"
TOOL="${REPO_ROOT}/bash/sysadmin-tool.sh"
export TESTS_DIR REPO_ROOT TOOL

# External commands the tool needs to start and run
# options 1-5 (without rsync, to force the cp backup) (used to build a minimal, controlled PATH).
MIN_PATH_CMDS=(bash getent df find sort head tail awk du findmnt lsblk date
    hostname clear mktemp rm numfmt tr wc cat cp mkdir basename sync ls
    sleep chmod)

# ---------------------------------------------------------------------------
# Running the tool
# ---------------------------------------------------------------------------

# run_tool [line...]
# Runs the whole tool (menu), feeding stdin one line per
# argument. With no arguments, stdin is empty (immediate EOF).
# Leaves $status and $output (stdout+stderr) like any BATS "run".
run_tool() {
    if (($# == 0)); then
        run bash "${TOOL}" </dev/null
    else
        run bash "${TOOL}" < <(printf '%s\n' "$@")
    fi
}

# run_tool_stdout [line...]
# Same as run_tool but keeps stderr separate (available in $stderr).
run_tool_stdout() {
    if (($# == 0)); then
        run --separate-stderr bash "${TOOL}" </dev/null
    else
        run --separate-stderr bash "${TOOL}" < <(printf '%s\n' "$@")
    fi
}

# run_fn 'bash code'
# Sources the tool in a fresh bash and runs the given code.
# When sourced, only the functions are defined (main does not run).
# A separate process is used because the script enables "set -uo pipefail".
run_fn() {
    run bash -c 'source "$1" || exit 99; eval "$2"' _ "${TOOL}" "$1"
}

# ---------------------------------------------------------------------------
# Temporary directories and stubs
# ---------------------------------------------------------------------------

# make_temp_dir [name]
# Creates a directory inside BATS_TEST_TMPDIR (BATS removes it at the end) and
# prints its absolute physical path.
make_temp_dir() {
    local dir
    dir="$(mktemp -d "${BATS_TEST_TMPDIR}/${1:-dir}.XXXXXX")" || return 1
    (cd -P -- "${dir}" && pwd -P)
}

# make_stub_dir
# Creates a directory for fake binaries and stores it in STUB_DIR.
make_stub_dir() {
    STUB_DIR="$(make_temp_dir stubs)"
    export STUB_DIR
}

# make_stub name <<'EOF' ... EOF
# Creates a fake executable in STUB_DIR whose body is read from stdin.
make_stub() {
    local name="$1"
    [[ -n "${STUB_DIR:-}" ]] || make_stub_dir
    {
        printf '#!/usr/bin/env bash\n'
        cat
    } >"${STUB_DIR}/${name}"
    chmod +x "${STUB_DIR}/${name}"
}

# make_min_path
# Creates a directory with symlinks only to the commands in
# MIN_PATH_CMDS and stores its path in MIN_PATH. Allows simulating the absence of
# lastlog2/lastlog/last even if they are installed on the system.
make_min_path() {
    local cmd src
    MIN_PATH="$(make_temp_dir minpath)"
    for cmd in "${MIN_PATH_CMDS[@]}"; do
        if src="$(command -v "${cmd}")"; then
            ln -s "${src}" "${MIN_PATH}/${cmd}"
        fi
    done
    export MIN_PATH
}

# ---------------------------------------------------------------------------
# Privileges and utilities
# ---------------------------------------------------------------------------

require_root() {
    [[ "${EUID}" -eq 0 ]] || skip 'requiere root (ejecute con sudo)'
}

require_non_root() {
    [[ "${EUID}" -ne 0 ]] || skip 'requiere un usuario sin privilegios (root ignora los permisos)'
}

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "${cmd}" >/dev/null 2>&1 || skip "falta el comando '${cmd}'"
    done
}

# Extracts from $output the rows of the option 3 table (those starting
# with "  N  "), one per line.
# shellcheck disable=SC2154  # $output is defined by BATS "run"
largest_rows() {
    grep -E '^ *[0-9]+  +[0-9]+  ' <<<"${output}" || true
}

# Mounts and loop devices registered to be cleaned up in teardown.
CLEANUP_MOUNTS=()
CLEANUP_LOOPS=()

# mount_tmpfs dir: mounts a small tmpfs (requires root).
mount_tmpfs() {
    mkdir -p -- "$1"
    mount -t tmpfs -o size=4m tmpfs "$1" || return 1
    CLEANUP_MOUNTS+=("$1")
}

# make_loop_ext4 img: creates a 16 MiB ext4 image, attaches it to a loop and
# stores the device in LOOP_DEV (requires root).
make_loop_ext4() {
    local img="$1"
    truncate -s 16M -- "${img}" || return 1
    mkfs.ext4 -q -F -- "${img}" >/dev/null 2>&1 || return 1
    LOOP_DEV="$(losetup -f --show -- "${img}")" || return 1
    CLEANUP_LOOPS+=("${LOOP_DEV}")
}

# mount_loop dev dir: mounts the device on dir (requires root).
mount_loop() {
    mkdir -p -- "$2"
    mount -- "$1" "$2" || return 1
    CLEANUP_MOUNTS+=("$2")
}

# cleanup_mounts: unmounts (in reverse order) and frees loops. Call from
# teardown in tests that use mount_tmpfs/make_loop_ext4.
cleanup_mounts() {
    local i
    for ((i = ${#CLEANUP_MOUNTS[@]} - 1; i >= 0; i--)); do
        umount -l -- "${CLEANUP_MOUNTS[i]}" 2>/dev/null || true
    done
    for i in "${CLEANUP_LOOPS[@]}"; do
        losetup -d "${i}" 2>/dev/null || true
    done
    CLEANUP_MOUNTS=()
    CLEANUP_LOOPS=()
}

# restore_perms dir: restores permissions so BATS can delete the tree.
restore_perms() {
    chmod -R u+rwx -- "$1" 2>/dev/null || true
}
