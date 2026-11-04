#!/usr/bin/env bats
# shellcheck disable=SC2143  # "! grep" does not fail a BATS test; [ -z "$(grep ...)" ] is used
#
# Option 2: filesystems (df -B1), pseudo-FS exclusion,
# column alignment and mount points with spaces.

load test_helper

teardown() {
    cleanup_mounts
}

# Extracts the df table (from the header to the blank line preceding
# "Discos físicos").
fs_table() {
    sed -n '/^DISPOSITIVO /,/^$/p' <<<"$output" | sed '/^$/d'
}

# Data rows (no header or separator).
fs_rows() {
    fs_table | sed '1,2d'
}

# ---------------------------------------------------------------------------
# Unit
# ---------------------------------------------------------------------------

@test "max_length: devuelve la longitud del argumento más largo" {
    run_fn 'max_length a abcd ab'
    [ "$output" = "4" ]
}

@test "max_length: sin argumentos devuelve 0" {
    run_fn 'max_length'
    [ "$output" = "0" ]
}

@test "max_length: cuenta caracteres multibyte y espacios" {
    run_fn 'LC_ALL=C.UTF-8; max_length "/mnt/mi disco" "ñandú"'
    [ "$output" = "13" ]
}

# ---------------------------------------------------------------------------
# Integration
# ---------------------------------------------------------------------------

@test "opción 2: muestra cabecera, tabla y discos físicos (lsblk)" {
    run_tool 2 '' '' 0
    [ "$status" -eq 0 ]
    grep -Eq '^DISPOSITIVO +TIPO +TOTAL \(BYTES\) +DISPONIBLE \(BYTES\)  MONTAJE$' <<<"$output"
    grep -Eq '^-+$' <<<"$output"
    [[ "$output" == *"Discos físicos (lsblk -b):"* ]]
}

@test "opción 2: por defecto excluye tmpfs, devtmpfs, squashfs y overlay" {
    run_tool 2 '' '' 0
    [ "$status" -eq 0 ]
    local types
    types="$(fs_rows | awk '{ print $2 }')"
    [ -n "$types" ]
    [ -z "$(grep -Ex 'tmpfs|devtmpfs|squashfs|overlay' <<<"$types")" ]
}

@test "opción 2: respuesta 'n' también excluye pseudo-FS" {
    run_tool 2 n '' 0
    [ -z "$(fs_rows | awk '{ print $2 }' | grep -Ex 'tmpfs|devtmpfs|squashfs|overlay')" ]
}

@test "opción 2: respuesta 's' incluye pseudo-FS presentes en el sistema" {
    LC_ALL=C df --output=fstype | grep -Exq 'tmpfs|overlay|devtmpfs|squashfs' ||
        skip 'el sistema no tiene pseudo-FS montados'
    run_tool 2 s '' 0
    [ "$status" -eq 0 ]
    fs_rows | awk '{ print $2 }' | grep -Exq 'tmpfs|devtmpfs|squashfs|overlay'
}

@test "opción 2: respuesta 'S' (mayúscula) también incluye pseudo-FS" {
    LC_ALL=C df --output=fstype | grep -Exq 'tmpfs|overlay' || skip 'sin tmpfs/overlay'
    run_tool 2 S '' 0
    fs_rows | awk '{ print $2 }' | grep -Exq 'tmpfs|overlay'
}

@test "opción 2: 'si' no se interpreta como sí (solo s/S)" {
    run_tool 2 si '' 0
    [ -z "$(fs_rows | awk '{ print $2 }' | grep -Ex 'tmpfs|devtmpfs|squashfs|overlay')" ]
}

@test "opción 2: tamaños en bytes coinciden con df -B1 para /" {
    local expected
    expected="$(LC_ALL=C df -B1 --output=size / | tail -n 1 | tr -d ' ')"
    run_tool 2 '' '' 0
    local row
    row="$(fs_rows | awk '$NF == "/"')"
    [ -n "$row" ]
    [ "$(awk '{ print $3 }' <<<"$row")" = "$expected" ]
    # Available: integer in bytes, not greater than the total.
    local avail
    avail="$(awk '{ print $4 }' <<<"$row")"
    [[ "$avail" =~ ^[0-9]+$ ]]
    [ "$avail" -le "$expected" ]
}

@test "opción 2: el número de filas coincide con df con las mismas exclusiones" {
    local expected
    expected="$(LC_ALL=C df -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs \
        -x ramfs -x rootfs -x proc -x sysfs -x devpts -x cgroup -x cgroup2 -x autofs \
        --output=target 2>/dev/null | tail -n +2 | wc -l)"
    run_tool 2 '' '' 0
    [ "$(fs_rows | wc -l)" -eq "$expected" ]
}

@test "opción 2: columnas alineadas (todas las filas con el mismo formato)" {
    run_tool 2 s '' 0
    local table header pos_type pos_mnt line sep
    table="$(fs_table)"
    header="$(head -n 1 <<<"$table")"
    sep="$(sed -n 2p <<<"$table")"
    pos_type="$(awk '{ print index($0, "TIPO") }' <<<"$header")"
    pos_mnt="$(awk '{ print index($0, "MONTAJE") }' <<<"$header")"
    [ "$pos_type" -gt 1 ]
    [ "$pos_mnt" -gt "$pos_type" ]
    # The separator spans the whole table width up to MONTAJE.
    [ "${#sep}" -ge "$((pos_mnt - 1))" ]
    while IFS= read -r line; do
        # Before TIPO there are two spaces, and MONTAJE starts with '/' (or is a
        # mount name) in exactly the same column as the header.
        [ "${line:pos_type-3:2}" = "  " ]
        [ "${line:pos_type-1:1}" != " " ]
        [ "${line:pos_mnt-3:2}" = "  " ]
        [ "${line:pos_mnt-1:1}" != " " ]
        # Numeric columns are right-aligned.
        [[ "${line:pos_mnt-4:1}" =~ [0-9] ]]
    done < <(sed '1,2d' <<<"$table")
}

@test "opción 2 (root): punto de montaje con espacios se muestra completo" {
    require_root
    require_cmd mkfs.ext4 losetup
    local dir mnt
    dir="$(make_temp_dir fs)"
    mnt="${dir}/disco con  espacios"
    make_loop_ext4 "${dir}/img"
    mount_loop "${LOOP_DEV}" "${mnt}"
    run_tool 2 '' '' 0
    [ "$status" -eq 0 ]
    local row
    row="$(fs_rows | grep -F "${LOOP_DEV} ")"
    [ -n "$row" ]
    [[ "$row" == *"  ${mnt}" ]]
    [ "$(awk '{ print $2 }' <<<"$row")" = "ext4" ]
    [ "$(awk '{ print $3 }' <<<"$row")" = "$(LC_ALL=C df -B1 --output=size "${mnt}" | tail -n 1 | tr -d ' ')" ]
}

@test "opción 2 (root): tmpfs nuevo aparece solo al responder 's'" {
    require_root
    local dir mnt
    dir="$(make_temp_dir fs)"
    mnt="${dir}/tmp fs"
    mount_tmpfs "${mnt}"
    run_tool 2 '' '' 0
    [ -z "$(fs_rows | grep -F "${mnt}")" ]
    run_tool 2 s '' 0
    local row
    row="$(fs_rows | grep -F "${mnt}")"
    [[ "$row" == *"  ${mnt}" ]]
    [ "$(awk '{ print $2 }' <<<"$row")" = "tmpfs" ]
    [ "$(awk '{ print $3 }' <<<"$row")" = "4194304" ]
}
