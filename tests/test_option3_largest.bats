#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # literal code evaluated in another bash
#
# Option 3: the ten largest files of a device or
# mount point (find -xdev, sort -z, head -z).

load test_helper

setup() {
    DATA="$(make_temp_dir data)"
}

teardown() {
    cleanup_mounts
    restore_perms "${BATS_TEST_TMPDIR}"
}

# Creates a file of N bytes.
mkfile() {
    head -c "$2" /dev/zero >"$1"
}

# ---------------------------------------------------------------------------
# Unit: resolve_search_path and human_size
# ---------------------------------------------------------------------------

@test "resolve_search_path: directorio relativo devuelve ruta absoluta física" {
    mkdir -p "${DATA}/sub"
    ln -s "${DATA}/sub" "${DATA}/enlace"
    cd "${DATA}"
    run_fn 'resolve_search_path enlace'
    [ "$status" -eq 0 ]
    [ "$output" = "${DATA}/sub" ]
}

@test "resolve_search_path: ruta inexistente da error 'no existe'" {
    run_fn "resolve_search_path '${DATA}/nada'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: '${DATA}/nada' no existe."* ]]
}

@test "resolve_search_path: archivo regular da error" {
    : >"${DATA}/f"
    run_fn "resolve_search_path '${DATA}/f'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no es un directorio ni un dispositivo de bloques"* ]]
}

@test "resolve_search_path: dispositivo montado se traduce a su punto de montaje" {
    local src target
    src="$(findmnt -n -f -o SOURCE /)"
    [ -b "$src" ] || skip "la raíz no está sobre un dispositivo de bloques ($src)"
    target="$(findmnt -n -f -o TARGET --source "$src")"
    run_fn "resolve_search_path '$src'"
    [ "$status" -eq 0 ]
    [ "$output" = "$target" ]
}

@test "resolve_search_path: dispositivo de bloques no montado da error" {
    local dev='' d
    for d in /dev/sd? /dev/vd? /dev/loop[0-9]*; do
        [ -b "$d" ] || continue
        if [ -z "$(findmnt -n -o TARGET --source "$d" 2>/dev/null)" ] &&
            [ -z "$(lsblk -nr -o MOUNTPOINT "$d" 2>/dev/null | tr -d '\n')" ]; then
            dev="$d"
            break
        fi
    done
    [ -n "$dev" ] || skip 'no hay dispositivos de bloques sin montar'
    run_fn "resolve_search_path '$dev'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"el dispositivo '$dev' no está montado"* ]]
}

@test "resolve_search_path: directorio sin permiso de acceso da error" {
    require_non_root
    mkdir "${DATA}/cerrado"
    chmod 000 "${DATA}/cerrado"
    run_fn "resolve_search_path '${DATA}/cerrado'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no hay permiso para acceder"* ]]
}

@test "human_size: unidades IEC con numfmt" {
    run_fn 'human_size 0; human_size 512; human_size 1024; human_size 1536; human_size 1073741824'
    [ "$output" = $'0B\n512B\n1.0KiB\n1.5KiB\n1.0GiB' ]
}

@test "human_size: respaldo con awk cuando no hay numfmt" {
    make_min_path
    rm -f "${MIN_PATH}/numfmt"
    PATH="${MIN_PATH}" run_fn 'human_size 512; human_size 1536; human_size 1073741824'
    [ "$output" = $'512B\n1.5 KiB\n1.0 GiB' ]
}

# ---------------------------------------------------------------------------
# Integration: input validation
# ---------------------------------------------------------------------------

@test "opción 3: entrada vacía muestra error y vuelve al menú" {
    run_tool 3 '' '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: no se ingresó ninguna ruta."* ]]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "opción 3: ruta inexistente muestra error" {
    run_tool 3 "${DATA}/no-existe" '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: '${DATA}/no-existe' no existe."* ]]
    [[ "$output" != *"Buscando en:"* ]]
}

@test "opción 3: ruta con espacios al inicio y al final se respeta" {
    mkdir "${DATA}/  con espacios  "
    mkfile "${DATA}/  con espacios  /x" 10
    run_tool 3 "${DATA}/  con espacios  " '' 0
    [[ "$output" == *"Buscando en: ${DATA}/  con espacios  "* ]]
    grep -Fq "  ${DATA}/  con espacios  /x" <<<"$output"
}

@test "opción 3: '~' y '~/sub' se expanden a \$HOME" {
    mkdir "${DATA}/sub"
    mkfile "${DATA}/sub/en_home" 10
    HOME="${DATA}" run_tool 3 '~/sub' '' 0
    [[ "$output" == *"Buscando en: ${DATA}/sub"* ]]
    grep -Fq "  ${DATA}/sub/en_home" <<<"$output"
    HOME="${DATA}" run_tool 3 '~' '' 0
    [[ "$output" == *"Buscando en: ${DATA}"$'\n'* ]]
}

@test "opción 3: archivo regular muestra error" {
    : >"${DATA}/archivo"
    run_tool 3 "${DATA}/archivo" '' 0
    [[ "$output" == *"no es un directorio ni un dispositivo de bloques"* ]]
}

# ---------------------------------------------------------------------------
# Integration: results
# ---------------------------------------------------------------------------

# numfmt rounds "from zero": 15000 B = 14.648 KiB -> 14.7KiB.

@test "opción 3: máximo 10 resultados ordenados de mayor a menor" {
    local i
    for i in $(seq 1 15); do mkfile "${DATA}/f${i}" $((i * 1000)); done
    run_tool 3 "${DATA}" '' 0
    [ "$status" -eq 0 ]
    local rows
    rows="$(largest_rows)"
    [ "$(wc -l <<<"$rows")" -eq 10 ]
    [ "$(awk '{ print $2 }' <<<"$rows" | tr '\n' ' ')" = "15000 14000 13000 12000 11000 10000 9000 8000 7000 6000 " ]
    [ "$(awk '{ print $1 }' <<<"$rows" | tr '\n' ' ')" = "1 2 3 4 5 6 7 8 9 10 " ]
    grep -Eq "^  1  +15000  +14\.7KiB  ${DATA}/f15$" <<<"$rows"
}

@test "opción 3: tamaño en bytes y legible coinciden con stat/numfmt" {
    mkfile "${DATA}/grande" 3145728
    mkfile "${DATA}/chico" 100
    run_tool 3 "${DATA}" '' 0
    grep -Eq "^  1  +3145728  +3\.0MiB  ${DATA}/grande$" <<<"$output"
    grep -Eq "^  2  +100  +100B  ${DATA}/chico$" <<<"$output"
}

@test "opción 3: menos de 10 archivos muestra solo los existentes" {
    mkfile "${DATA}/a" 10
    mkfile "${DATA}/b" 20
    run_tool 3 "${DATA}" '' 0
    [ "$(largest_rows | wc -l)" -eq 2 ]
}

@test "opción 3: directorio vacío informa que no hay archivos" {
    run_tool 3 "${DATA}" '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"No se encontraron archivos regulares en ${DATA}."* ]]
}

@test "opción 3: solo cuenta archivos regulares (ignora enlaces y directorios)" {
    mkfile "${DATA}/real" 50
    ln -s /etc/passwd "${DATA}/enlace"
    mkdir "${DATA}/dir"
    run_tool 3 "${DATA}" '' 0
    local rows
    rows="$(largest_rows)"
    [ "$(wc -l <<<"$rows")" -eq 1 ]
    [[ "$rows" == *"${DATA}/real" ]]
}

@test "opción 3: ruta relativa produce rutas absolutas" {
    mkdir "${DATA}/rel"
    mkfile "${DATA}/rel/x" 10
    cd "${DATA}"
    run_tool 3 rel '' 0
    [[ "$output" == *"Buscando en: ${DATA}/rel"* ]]
    grep -Eq "  ${DATA}/rel/x$" <<<"$(largest_rows)"
}

@test "opción 3: directorio que no es punto de montaje muestra la nota" {
    mkfile "${DATA}/x" 1
    run_tool 3 "${DATA}" '' 0
    [[ "$output" == *"Nota: no es un punto de montaje; pertenece al sistema de archivos montado en"* ]]
}

@test "opción 3: archivos en subdirectorios profundos se encuentran" {
    mkdir -p "${DATA}/a/b/c/d"
    mkfile "${DATA}/a/b/c/d/hondo" 999
    run_tool 3 "${DATA}" '' 0
    grep -Eq "^  1  +999  .*  ${DATA}/a/b/c/d/hondo$" <<<"$output"
}

@test "opción 3: nombres con espacios se muestran completos" {
    mkfile "${DATA}/mi archivo  con espacios.txt" 300
    run_tool 3 "${DATA}" '' 0
    grep -Fq "  ${DATA}/mi archivo  con espacios.txt" <<<"$output"
}

@test "opción 3: nombres con tabulador interno se muestran completos" {
    mkfile "${DATA}/con"$'\t'"tab" 300
    run_tool 3 "${DATA}" '' 0
    grep -Fq "  ${DATA}/con"$'\t'"tab" <<<"$output"
}

@test "opción 3: nombre que termina en tabulador conserva el tabulador" {
    mkfile "${DATA}/fin"$'\t' 300
    run_tool 3 "${DATA}" '' 0
    grep -q "${DATA}/fin"$'\t'"\$" <<<"$output"
}

@test "opción 3: nombres con salto de línea se muestran como \\n en una fila" {
    mkfile "${DATA}/linea1"$'\n'"linea2" 300
    run_tool 3 "${DATA}" '' 0
    grep -Fq "  ${DATA}/linea1\\nlinea2" <<<"$output"
    [ "$(largest_rows | wc -l)" -eq 1 ]
}

@test "opción 3: caracteres especiales (\$ * ? [ ] ' \" \\ ñ) se muestran literal" {
    local name='a$b*c?d[e]f'\''g"h\i ñ.txt'
    mkfile "${DATA}/${name}" 300
    run_tool 3 "${DATA}" '' 0
    grep -Fq "  ${DATA}/${name}" <<<"$output"
}

@test "opción 3: nombre que empieza con guion no se confunde con opción" {
    mkfile "${DATA}/-n" 300
    run_tool 3 "${DATA}" '' 0
    grep -Fq "  ${DATA}/-n" <<<"$output"
}

@test "opción 3: archivo vacío (0 bytes) aparece con 0" {
    : >"${DATA}/vacio"
    run_tool 3 "${DATA}" '' 0
    grep -Eq "^  1  +0  +0B  ${DATA}/vacio$" <<<"$output"
}

@test "opción 3 (no root): directorio ilegible genera advertencia de permisos" {
    require_non_root
    mkdir "${DATA}/privado"
    mkfile "${DATA}/privado/secreto" 5000
    mkfile "${DATA}/visible" 10
    chmod 000 "${DATA}/privado"
    run_tool 3 "${DATA}" '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA: sin privilegios de root algunos directorios pueden no ser accesibles."* ]]
    [[ "$output" == *"ADVERTENCIA: find no pudo leer 1 ruta(s)"* ]]
    [[ "$output" != *secreto* ]]
    grep -Fq "  ${DATA}/visible" <<<"$output"
}

@test "opción 3 (root): no muestra advertencias de permisos" {
    require_root
    mkdir "${DATA}/privado"
    mkfile "${DATA}/privado/secreto" 5000
    chmod 000 "${DATA}/privado"
    run_tool 3 "${DATA}" '' 0
    [[ "$output" != *"sin privilegios de root"* ]]
    [[ "$output" != *"find no pudo leer"* ]]
    grep -Fq "  ${DATA}/privado/secreto" <<<"$output"
}

@test "opción 3 (root): -xdev no entra en un sistema de archivos montado dentro" {
    require_root
    mkfile "${DATA}/fuera" 100
    mount_tmpfs "${DATA}/anidado"
    mkfile "${DATA}/anidado/dentro" 2000000
    run_tool 3 "${DATA}" '' 0
    [[ "$output" != *"/anidado/dentro"* ]]
    grep -Fq "  ${DATA}/fuera" <<<"$output"
}

@test "opción 3 (root): punto de montaje exacto no muestra la nota" {
    require_root
    mount_tmpfs "${DATA}/mnt"
    mkfile "${DATA}/mnt/f" 10
    run_tool 3 "${DATA}/mnt" '' 0
    [[ "$output" == *"Buscando en: ${DATA}/mnt"* ]]
    [[ "$output" != *"Nota: no es un punto de montaje"* ]]
}

@test "opción 3 (root): dispositivo loop montado se busca en su punto de montaje" {
    require_root
    require_cmd mkfs.ext4 losetup
    make_loop_ext4 "${DATA}/qa_img"
    mount_loop "${LOOP_DEV}" "${DATA}/qa mnt"
    mkfile "${DATA}/qa mnt/en el loop" 12345
    run_tool 3 "${LOOP_DEV}" '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Buscando en: ${DATA}/qa mnt"* ]]
    grep -Eq "^  1  +12345  .*  ${DATA}/qa mnt/en el loop$" <<<"$output"
}

@test "opción 3 (root): dispositivo loop sin montar da error" {
    require_root
    require_cmd mkfs.ext4 losetup
    make_loop_ext4 "${BATS_TEST_TMPDIR}/qa_img2"
    run_tool 3 "${LOOP_DEV}" '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: el dispositivo '${LOOP_DEV}' no está montado; móntelo antes de buscar."* ]]
}
