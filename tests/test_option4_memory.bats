#!/usr/bin/env bats
# shellcheck disable=SC2016  # literal code evaluated in another bash
#
# Option 4: RAM and swap from /proc/meminfo (values in bytes).
# Cases with a fake /proc/meminfo use "unshare -m" (root) or
# "unshare -rm" (regular user with user namespaces).

load test_helper

# Value in bytes that the tool prints for a given label.
mem_value() {
    grep -F "$1" <<<"$output" | awk '{ for (i = 1; i <= NF; i++) if ($i == "bytes") { print $(i - 1); exit } }'
}

# Percentage printed on a label's line (without the % sign).
mem_percent() {
    grep -F "$1" <<<"$output" | awk '{ print $(NF - 1) }'
}

# run_with_meminfo file: runs option 4 with a fake /proc/meminfo.
run_with_meminfo() {
    local fake="$1"
    local -a ns
    if [[ "${EUID}" -eq 0 ]]; then
        ns=(unshare -m)
    else
        ns=(unshare -rm)
    fi
    "${ns[@]}" true 2>/dev/null || skip 'unshare no disponible (sin espacios de nombres)'
    run "${ns[@]}" bash -c 'mount --bind "$1" /proc/meminfo || exit 98
        printf "4\n\n0\n" | bash "$2"' _ "${fake}" "${TOOL}"
    [ "$status" -ne 98 ] || skip 'no se pudo montar el /proc/meminfo falso'
}

@test "percentage: dos decimales y 0.00 con total cero" {
    run_fn 'percentage 1 3; percentage 50 200; percentage 5 0; percentage 0 10'
    [ "$output" = $'33.33\n25.00\n0.00\n0.00' ]
}

@test "opción 4: MemTotal en bytes = /proc/meminfo * 1024" {
    local expected
    expected="$(awk '/^MemTotal:/ { printf "%.0f", $2 * 1024 }' /proc/meminfo)"
    run_tool 4 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memoria RAM (fuente: /proc/meminfo)"* ]]
    [ "$(mem_value 'Total (MemTotal):')" = "$expected" ]
}

@test "opción 4: SwapTotal en bytes = /proc/meminfo * 1024" {
    local kib
    kib="$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)"
    run_tool 4 '' 0
    [ "$(mem_value 'Total (SwapTotal):')" = "$((kib * 1024))" ]
    if ((kib == 0)); then
        [[ "$output" == *"No hay swap configurada"* ]]
    else
        [[ "$output" == *"Usada (Total - Free):"* ]]
    fi
}

@test "opción 4: valores son múltiplos de 1024 y libre <= disponible <= total" {
    run_tool 4 '' 0
    local total free avail
    total="$(mem_value 'Total (MemTotal):')"
    free="$(mem_value 'Libre (MemFree):')"
    avail="$(mem_value 'Disponible (MemAvailable):')"
    [ $((total % 1024)) -eq 0 ]
    [ $((free % 1024)) -eq 0 ]
    [ $((avail % 1024)) -eq 0 ]
    [ "$free" -le "$total" ]
    [ "$avail" -le "$total" ]
}

@test "opción 4: porcentajes con dos decimales y coherentes con los bytes" {
    run_tool 4 '' 0
    local total free pct expected
    total="$(mem_value 'Total (MemTotal):')"
    free="$(mem_value 'Libre (MemFree):')"
    pct="$(mem_percent 'Libre (MemFree):')"
    [[ "$pct" =~ ^[0-9]+\.[0-9]{2}$ ]]
    expected="$(awk -v p="$free" -v t="$total" 'BEGIN { printf "%.2f", p * 100 / t }')"
    [ "$pct" = "$expected" ]
    [[ "$(mem_percent 'Disponible (MemAvailable):')" =~ ^[0-9]+\.[0-9]{2}$ ]]
}

@test "opción 4: incluye tamaño legible (KiB/MiB/GiB)" {
    run_tool 4 '' 0
    grep -F 'Total (MemTotal):' <<<"$output" | grep -Eq '[0-9]+\.[0-9](KiB|MiB|GiB|TiB)'
}

@test "opción 4 (meminfo falso): valores exactos y porcentajes" {
    local fake="${BATS_TEST_TMPDIR}/meminfo"
    cat >"$fake" <<'EOF'
MemTotal:        1000 kB
MemFree:          250 kB
MemAvailable:     500 kB
Buffers:           10 kB
Cached:            20 kB
SwapTotal:       2000 kB
SwapFree:        1500 kB
EOF
    run_with_meminfo "$fake"
    [ "$status" -eq 0 ]
    [ "$(mem_value 'Total (MemTotal):')" = "1024000" ]
    [ "$(mem_value 'Libre (MemFree):')" = "256000" ]
    [ "$(mem_percent 'Libre (MemFree):')" = "25.00" ]
    [ "$(mem_value 'Disponible (MemAvailable):')" = "512000" ]
    [ "$(mem_percent 'Disponible (MemAvailable):')" = "50.00" ]
    [ "$(mem_value 'Total (SwapTotal):')" = "2048000" ]
    [ "$(mem_value 'Usada (Total - Free):')" = "512000" ]
    [ "$(mem_percent 'Usada (Total - Free):')" = "25.00" ]
    [[ "$output" != *"no expone MemAvailable"* ]]
}

@test "opción 4 (meminfo falso): SwapTotal=0 no divide por cero" {
    local fake="${BATS_TEST_TMPDIR}/meminfo"
    printf 'MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 200 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' >"$fake"
    run_with_meminfo "$fake"
    [ "$status" -eq 0 ]
    [ "$(mem_value 'Total (SwapTotal):')" = "0" ]
    [[ "$output" == *"No hay swap configurada; el uso es 0 bytes y el porcentaje no aplica."* ]]
    [[ "$output" != *"Usada (Total - Free):"* ]]
    [[ "$output" != *"division"* ]]
}

@test "opción 4 (meminfo falso): sin MemAvailable se estima y advierte" {
    local fake="${BATS_TEST_TMPDIR}/meminfo"
    printf 'MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 150 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' >"$fake"
    run_with_meminfo "$fake"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA: el kernel no expone MemAvailable; se estimó como MemFree + Buffers + Cached."* ]]
    [ "$(mem_value 'Disponible (MemAvailable):')" = "307200" ]
    [ "$(mem_percent 'Disponible (MemAvailable):')" = "30.00" ]
}

@test "opción 4 (meminfo falso): sin líneas Swap se trata como sin swap" {
    local fake="${BATS_TEST_TMPDIR}/meminfo"
    printf 'MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 200 kB\n' >"$fake"
    run_with_meminfo "$fake"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No hay swap configurada"* ]]
}

@test "opción 4 (meminfo falso): valores grandes (TiB) sin notación científica" {
    local fake="${BATS_TEST_TMPDIR}/meminfo"
    printf 'MemTotal: 4294967296 kB\nMemFree: 1073741824 kB\nMemAvailable: 2147483648 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' >"$fake"
    run_with_meminfo "$fake"
    [ "$(mem_value 'Total (MemTotal):')" = "4398046511104" ]
    [ "$(mem_percent 'Libre (MemFree):')" = "25.00" ]
    [[ "$output" != *"e+"* ]]
}

@test "opción 4 (meminfo falso): archivo sin MemTotal da error" {
    local fake="${BATS_TEST_TMPDIR}/meminfo"
    printf 'Basura: 1 kB\n' >"$fake"
    run_with_meminfo "$fake"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: no se pudo interpretar /proc/meminfo."* ]]
}
