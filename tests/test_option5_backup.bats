#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2088,SC2143  # literal code for run_fn/bash -c; variables exported per test
#
# Option 5: backup to a USB drive. No real USB is required: the
# destination is entered manually (option "m") or detection is simulated with
# a fake lsblk. Input sequence:
#   5, source, destination (1..N | m | c), [path if m], confirmation y/n, Enter, 0

load test_helper

setup() {
    SRC_PARENT="$(make_temp_dir origen)"
    SRC="${SRC_PARENT}/datos"
    mkdir -p "${SRC}/sub/profundo"
    printf 'hola\n' >"${SRC}/a.txt"
    head -c 5000 /dev/urandom >"${SRC}/sub/b.bin"
    printf 'x' >"${SRC}/sub/profundo/c"
    DEST="$(make_temp_dir destino)"
    SHM_DEST=''
}

teardown() {
    cleanup_mounts
    restore_perms "${BATS_TEST_TMPDIR}"
    if [[ -n "${SHM_DEST}" ]]; then
        rm -rf -- "${SHM_DEST}"
    fi
}

# on_root_fs DEST: true if DEST belongs to the root filesystem
# "/". In that case the tool asks for an extra confirmation
# ("¿Seguro que desea usar este destino?") before "¿Iniciar la copia?".
on_root_fs() {
    [ -d "$1" ] && [ "$(findmnt -n -o TARGET -T "$1" 2>/dev/null)" = / ]
}

# backup_lines SRC DEST [confirmation]: leaves in BACKUP_IN the input lines
# of a backup with a manual destination (without the pause Enter or the 0).
backup_lines() {
    BACKUP_IN=(5 "$1" m "$2")
    if on_root_fs "$2"; then
        BACKUP_IN+=(s)
    fi
    BACKUP_IN+=("${3-s}")
}

# backup SRC DEST [confirmation]: runs option 5 with a manual destination.
backup() {
    backup_lines "$@"
    run_tool "${BACKUP_IN[@]}" '' 0
}

# Value of a summary field ("  Label:   value").
summary_field() {
    grep -F "  $1" <<<"$output" | head -n 1 | sed -E "s/^  $1 +//"
}

# Destination on another filesystem (tmpfs /dev/shm) to avoid getting the
# "same filesystem" warning.
other_fs_dest() {
    [ -d /dev/shm ] && [ -w /dev/shm ] || skip '/dev/shm no disponible'
    [ "$(findmnt -n -o TARGET -T /dev/shm)" != "$(findmnt -n -o TARGET -T "${SRC}")" ] ||
        skip '/dev/shm está en el mismo sistema de archivos'
    SHM_DEST="$(mktemp -d /dev/shm/qa_backup.XXXXXX)"
}

# ---------------------------------------------------------------------------
# Unit
# ---------------------------------------------------------------------------

@test "unique_backup_dir: nombre libre se devuelve sin cambios" {
    run_fn "unique_backup_dir '${DEST}/backup_x_20260101_000000'"
    [ "$output" = "${DEST}/backup_x_20260101_000000" ]
}

@test "unique_backup_dir: nombres ocupados reciben sufijo _1, _2" {
    mkdir "${DEST}/b" "${DEST}/b_1"
    run_fn "unique_backup_dir '${DEST}/b'"
    [ "$output" = "${DEST}/b_2" ]
    rmdir "${DEST}/b_1"
    run_fn "unique_backup_dir '${DEST}/b'"
    [ "$output" = "${DEST}/b_1" ]
}

@test "is_fat_filesystem: vfat/msdos/fat/exfat sí; ext4/ntfs no" {
    run_fn 'for t in vfat msdos fat exfat; do is_fat_filesystem $t || exit 1; done
        for t in ext4 ntfs xfs ""; do is_fat_filesystem "$t" && exit 2; done; exit 0'
    [ "$status" -eq 0 ]
}

@test "tree_stats: cuenta archivos regulares y suma bytes" {
    run_fn "tree_stats '${SRC}'"
    [ "$output" = "3 5006" ]
}

@test "print_field: alinea etiquetas con tildes por caracteres, no bytes" {
    run bash -c 'export LC_ALL=C.UTF-8; source "$1"; print_field "Catálogo:" v; print_field "Origen:" v' _ "${TOOL}"
    local l1 l2
    l1="$(sed -n 1p <<<"$output")"
    l2="$(sed -n 2p <<<"$output")"
    [ "${#l1}" -eq "${#l2}" ]
}

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------

@test "opción 5: copia exitosa a otro sistema de archivos (destino manual)" {
    other_fs_dest
    backup "${SRC}" "${SHM_DEST}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verificación:"*"EXITOSA (cantidad y tamaño total coinciden)"* ]]
    [[ "$output" != *"mismo sistema de archivos"* ]]
    [[ "$output" == *"El dispositivo NO fue desmontado"* ]]
    local bdir
    bdir="$(summary_field 'Carpeta de respaldo:')"
    [[ "$bdir" =~ ^${SHM_DEST}/backup_datos_[0-9]{8}_[0-9]{6}$ ]]
    [ -d "${bdir}/datos" ]
    [ -f "${bdir}/catalogo.txt" ]
    diff -r "${SRC}" "${bdir}/datos"
}

@test "opción 5: mismo sistema de archivos advierte pero copia" {
    backup "${SRC}" "${DEST}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA: el destino está en el mismo sistema de archivos que el origen"* ]]
    [[ "$output" == *"EXITOSA"* ]]
    local bdir
    bdir="$(summary_field 'Carpeta de respaldo:')"
    diff -r "${SRC}" "${bdir}/datos"
}

@test "opción 5: resumen con conteo de archivos, bytes y método rsync" {
    command -v rsync >/dev/null || skip 'rsync no instalado'
    backup "${SRC}" "${DEST}"
    [ "$(summary_field 'Archivos regulares:')" = "origen 3 / copia 3" ]
    [ "$(summary_field 'Bytes en archivos:')" = "origen 5006 / copia 5006" ]
    [ "$(summary_field 'Método:')" = "rsync -a" ]
    [[ "$(summary_field 'Duración:')" =~ ^[0-9]+\ s$ ]]
}

@test "opción 5: catalogo.txt lista rutas relativas y fecha de modificación" {
    touch -d @1750000000 "${SRC}/a.txt"
    # Expected date with the same format and time zone that find uses.
    local expected
    expected="$(find "${SRC}/a.txt" -printf '%TY-%Tm-%Td %TH:%TM:%TS')"
    expected="${expected%%.*}"
    backup "${SRC}" "${DEST}"
    local bdir cat
    bdir="$(summary_field 'Carpeta de respaldo:')"
    cat="${bdir}/catalogo.txt"
    grep -Fq "# Catálogo de la copia de seguridad de: ${SRC}" "$cat"
    # Each entry: relative_path<TAB>YYYY-MM-DD HH:MM:SS
    grep -Fq "a.txt"$'\t'"${expected}" "$cat"
    diff <(grep -v '^#' "$cat" | cut -f1 | LC_ALL=C sort) \
        <(find "${SRC}" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)
    [ -z "$(grep -v '^#' "$cat" | grep -Pv '^[^\t/][^\t]*\t[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')" ]
}

@test "opción 5: conserva la fecha de modificación de los archivos" {
    touch -d '2024-01-02 03:04:05' "${SRC}/sub/b.bin"
    backup "${SRC}" "${DEST}"
    local bdir
    bdir="$(summary_field 'Carpeta de respaldo:')"
    [ "$(stat -c %Y "${SRC}/sub/b.bin")" = "$(stat -c %Y "${bdir}/datos/sub/b.bin")" ]
}

@test "opción 5: nombres con espacios y caracteres especiales" {
    local s="${SRC_PARENT}/mis datos (2026)"
    mkdir -p "$s/carpeta con espacio"
    printf '1' >"$s/carpeta con espacio/archivo ñandú.txt"
    printf '2' >"$s/"'raro $x *?[a] '\''"\.txt'
    printf '3' >"$s/-empieza-con-guion"
    printf '4' >"$s/con"$'\t'"tab"
    backup "$s" "${DEST}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXITOSA"* ]]
    local bdir
    bdir="$(summary_field 'Carpeta de respaldo:')"
    [[ "$bdir" == "${DEST}/backup_mis datos (2026)_"* ]]
    diff -r "$s" "${bdir}/mis datos (2026)"
}

@test "opción 5: directorio de origen vacío" {
    local s="${SRC_PARENT}/vacio"
    mkdir "$s"
    backup "$s" "${DEST}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXITOSA"* ]]
    [ "$(summary_field 'Archivos regulares:')" = "origen 0 / copia 0" ]
    local bdir
    bdir="$(summary_field 'Carpeta de respaldo:')"
    [ -d "${bdir}/vacio" ]
    [ -z "$(ls -A "${bdir}/vacio")" ]
}

@test "opción 5: origen con ruta relativa y barra final" {
    cd "${SRC_PARENT}"
    backup "datos/" "${DEST}"
    [[ "$output" == *"EXITOSA"* ]]
    [ "$(summary_field 'Origen:')" = "${SRC}" ]
}

@test "opción 5: dos copias en el mismo segundo van a carpetas distintas" {
    backup_lines "${SRC}" "${DEST}"
    run_tool "${BACKUP_IN[@]}" '' "${BACKUP_IN[@]}" '' 0
    [ "$status" -eq 0 ]
    [ "$(grep -c 'EXITOSA' <<<"$output")" -eq 2 ]
    local -a dirs
    mapfile -t dirs < <(find "${DEST}" -mindepth 1 -maxdepth 1 -type d -name 'backup_datos_*' | sort)
    [ "${#dirs[@]}" -eq 2 ]
    # If they share a timestamp, the second one must carry the _1 suffix.
    if [[ "${dirs[1]}" == "${dirs[0]}"_* ]]; then
        [ "${dirs[1]}" = "${dirs[0]}_1" ]
    fi
    diff -r "${SRC}" "${dirs[0]}/datos"
    diff -r "${SRC}" "${dirs[1]}/datos"
}

@test "opción 5: colisión de nombre forzada recibe sufijo _1" {
    # The folders of the next few seconds are pre-created to force the collision.
    local t
    for t in 0 1 2 3; do
        mkdir -p "${DEST}/backup_datos_$(date -d "+${t} seconds" '+%Y%m%d_%H%M%S')"
    done
    backup "${SRC}" "${DEST}"
    [[ "$output" == *"EXITOSA"* ]]
    [[ "$(summary_field 'Carpeta de respaldo:')" =~ _[0-9]{6}_1$ ]]
}

@test "opción 5: sin rsync usa 'cp -a' y verifica correctamente" {
    make_min_path
    [ ! -e "${MIN_PATH}/rsync" ]
    backup_lines "${SRC}" "${DEST}"
    PATH="${MIN_PATH}" run "${MIN_PATH}/bash" "${TOOL}" < <(printf '%s\n' "${BACKUP_IN[@]}" '' 0)
    [ "$status" -eq 0 ]
    [ "$(summary_field 'Método:')" = "cp -a" ]
    [[ "$output" == *"EXITOSA"* ]]
    diff -r "${SRC}" "$(summary_field 'Copia de archivos:')"
}

@test "opción 5: destino hermano con prefijo común (/x/datos2) no se considera dentro" {
    mkdir "${SRC_PARENT}/datos2"
    backup "${SRC}" "${SRC_PARENT}/datos2"
    [ "$status" -eq 0 ]
    [[ "$output" != *"no puede estar dentro"* ]]
    [[ "$output" == *"EXITOSA"* ]]
}

# ---------------------------------------------------------------------------
# Input errors
# ---------------------------------------------------------------------------

@test "opción 5: origen inexistente" {
    run_tool 5 "${SRC_PARENT}/nada" '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: el directorio de origen '${SRC_PARENT}/nada' no existe."* ]]
    [[ "$output" != *"Destinos disponibles"* ]]
}

@test "opción 5: origen es un archivo" {
    run_tool 5 "${SRC}/a.txt" '' 0
    [[ "$output" == *"ERROR: '${SRC}/a.txt' no es un directorio."* ]]
}

@test "opción 5: origen vacío (Enter) da error" {
    run_tool 5 '' '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR:"* ]]
    [[ "$output" != *"Destinos disponibles"* ]]
}

@test "opción 5 (no root): origen sin permiso de lectura" {
    require_non_root
    chmod 000 "${SRC}"
    run_tool 5 "${SRC}" '' 0
    [[ "$output" == *"ERROR: no tiene permiso de lectura sobre '${SRC}'."* ]]
}

@test "opción 5: destino dentro del origen" {
    backup "${SRC}" "${SRC}/sub"
    [[ "$output" == *"ERROR: el destino no puede estar dentro del directorio de origen."* ]]
    [ -z "$(find "${SRC}" -name 'backup_*')" ]
}

@test "opción 5: destino igual al origen" {
    backup "${SRC}" "${SRC}"
    [[ "$output" == *"ERROR: el destino no puede estar dentro del directorio de origen."* ]]
}

@test "opción 5: destino dentro del origen a través de un enlace simbólico" {
    ln -s "${SRC}/sub" "${SRC_PARENT}/atajo"
    backup "${SRC}" "${SRC_PARENT}/atajo"
    [[ "$output" == *"el destino no puede estar dentro del directorio de origen"* ]]
}

@test "opción 5: destino inexistente" {
    backup "${SRC}" "${DEST}/no-existe"
    [[ "$output" == *"ERROR: el destino '${DEST}/no-existe' no existe o no es un directorio."* ]]
}

@test "opción 5: destino es un archivo" {
    : >"${DEST}/f"
    backup "${SRC}" "${DEST}/f"
    [[ "$output" == *"no existe o no es un directorio"* ]]
}

@test "opción 5 (no root): destino sin permiso de escritura" {
    require_non_root
    chmod 555 "${DEST}"
    backup "${SRC}" "${DEST}"
    [[ "$output" == *"ERROR: no tiene permiso de escritura en '${DEST}'"* ]]
}

@test "opción 5: ruta manual vacía da error" {
    run_tool 5 "${SRC}" m '' '' 0
    [[ "$output" == *"ERROR: no se ingresó ninguna ruta de destino."* ]]
}

@test "opción 5: opción de destino inválida (x, 99)" {
    run_tool 5 "${SRC}" x '' 5 "${SRC}" 99 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: opción de destino no válida: 'x'."* ]]
    [[ "$output" == *"ERROR: opción de destino no válida: '99'."* ]]
}

@test "opción 5: opción de destino con cero a la izquierda (08) da error limpio" {
    run_tool 5 "${SRC}" 08 '' 0
    [[ "$output" == *"opción de destino no válida: '08'."* ]]
    [[ "$output" != *"value too great for base"* ]]
}

@test "opción 5: cancelar con 'c' no crea nada" {
    run_tool 5 "${SRC}" c '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Operación cancelada."* ]]
    [ -z "$(ls -A "${DEST}")" ]
}

@test "opción 5: rechazar la confirmación no crea nada" {
    backup "${SRC}" "${DEST}" n
    [ "$status" -eq 0 ]
    [[ "$output" == *"Operación cancelada."* ]]
    [ -z "$(ls -A "${DEST}")" ]
}

@test "opción 5: destino en / pide confirmación extra; 'n' cancela" {
    on_root_fs "${DEST}" || skip 'BATS_TEST_TMPDIR no está en el sistema de archivos raíz'
    run_tool 5 "${SRC}" m "${DEST}" n '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA: el destino está en el sistema de archivos raíz (/)"* ]]
    [[ "$output" == *"Operación cancelada."* ]]
    [[ "$output" != *"Calculando el tamaño"* ]]
    [ -z "$(ls -A "${DEST}")" ]
}

@test "opción 5: destino en otro montaje no pide la confirmación extra" {
    other_fs_dest
    [ "$(findmnt -n -o TARGET -T "${SHM_DEST}")" != / ] || skip '/dev/shm está en /'
    run_tool 5 "${SRC}" m "${SHM_DEST}" s '' 0
    [[ "$output" != *"sistema de archivos raíz (/)"* ]]
    [[ "$output" == *"EXITOSA"* ]]
}

@test "opción 5: origen con '~/' se expande a \$HOME" {
    backup_lines '~/datos' "${DEST}"
    HOME="${SRC_PARENT}" run_tool "${BACKUP_IN[@]}" '' 0
    [ "$(summary_field 'Origen:')" = "${SRC}" ]
    [[ "$output" == *"EXITOSA"* ]]
}

@test "opción 5: destino manual con '~' se expande a \$HOME" {
    backup_lines "${SRC}" "${DEST}"
    BACKUP_IN[3]='~'
    HOME="${DEST}" run_tool "${BACKUP_IN[@]}" '' 0
    [[ "$(summary_field 'Carpeta de respaldo:')" == "${DEST}/backup_datos_"* ]]
}

@test "opción 5: origen con espacios al inicio y al final se respeta" {
    local s="${SRC_PARENT}/  esp  "
    mkdir "$s"
    printf 'z' >"$s/z"
    backup "$s" "${DEST}"
    [ "$(summary_field 'Origen:')" = "$s" ]
    [[ "$output" == *"EXITOSA"* ]]
    diff -r "$s" "$(summary_field 'Copia de archivos:')"
}

@test "opción 5: catálogo muestra un nombre con salto de línea en una sola línea con '?'" {
    printf 'n' >"${SRC}/linea1"$'\n'"linea2"
    backup "${SRC}" "${DEST}"
    local cat
    cat="$(summary_field 'Carpeta de respaldo:')/catalogo.txt"
    grep -Pq '^linea1\?linea2\t' "$cat"
    [ -z "$(grep -x 'linea2.*' "$cat")" ]
}

@test "opción 5 (no root): directorio ilegible no provoca aviso de catálogo" {
    require_non_root
    mkdir "${SRC}/cerrado"
    chmod 000 "${SRC}/cerrado"
    backup "${SRC}" "${DEST}"
    [[ "$output" != *"no se pudo escribir catalogo.txt"* ]]
    [ -s "$(summary_field 'Carpeta de respaldo:')/catalogo.txt" ]
}

@test "opción 5: confirmación vacía (Enter) equivale a No" {
    backup "${SRC}" "${DEST}" ''
    [[ "$output" == *"Operación cancelada."* ]]
    [ -z "$(ls -A "${DEST}")" ]
}

@test "opción 5: sin USB detectadas muestra el aviso y las opciones m/c" {
    make_stub_dir
    make_stub lsblk <<'EOF'
case " $* " in
*" -dnpr "*|*" -npr "*) exit 0 ;;
*) exec /usr/bin/lsblk "$@" ;;
esac
EOF
    PATH="${STUB_DIR}:${PATH}" run_tool 5 "${SRC}" c '' 0
    [[ "$output" == *"(no se detectaron memorias USB montadas)"* ]]
    [[ "$output" == *"m) Ingresar una ruta de destino manualmente"* ]]
    [[ "$output" == *"c) Cancelar"* ]]
}

@test "opción 5: detecta como USB un disco reportado con TRAN=usb (lsblk falso)" {
    local root_src
    root_src="$(findmnt -n -f -o SOURCE /)"
    [ -b "$root_src" ] || skip 'la raíz no es un dispositivo de bloques'
    make_stub_dir
    export QA_DEV="$root_src"
    make_stub lsblk <<'EOF'
case " $* " in
*" -dnpr "*) printf '%s disk 0 0 usb\n/dev/qa_no_usb disk 0 0 sata\n' "$QA_DEV" ;;
*" -npr "*) printf '%s 100M\n' "$QA_DEV" ;;
*) exec /usr/bin/lsblk "$@" ;;
esac
EOF
    PATH="${STUB_DIR}:${PATH}" run_tool 5 "${SRC}" c '' 0
    [[ "$output" == *"1) ${root_src} (100M) montado en /"* ]]
    [[ "$output" != *"qa_no_usb"* ]]
}

# ---------------------------------------------------------------------------
# Incomplete backup and signals
# ---------------------------------------------------------------------------

@test "opción 5 (no root): archivo ilegible en el origen => verificación FALLIDA" {
    require_non_root
    printf 'secreto' >"${SRC}/privado"
    chmod 000 "${SRC}/privado"
    backup "${SRC}" "${DEST}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA: sin privilegios de root los archivos no legibles"* ]]
    [[ "$output" == *"ADVERTENCIA: la copia terminó con errores"* ]]
    [[ "$output" == *"FALLIDA (la copia está incompleta o difiere del origen)"* ]]
}

@test "opción 5: SIGTERM durante la copia avisa que quedó INCOMPLETA" {
    make_stub_dir
    make_stub rsync <<EOF
: >"${BATS_TEST_TMPDIR}/copiando"
sleep 3
EOF
    local out="${BATS_TEST_TMPDIR}/sig.out" pid rc=0
    backup_lines "${SRC}" "${DEST}"
    PATH="${STUB_DIR}:${PATH}" bash "${TOOL}" \
        < <(printf '%s\n' "${BACKUP_IN[@]}"; sleep 30) >"$out" 2>&1 &
    pid=$!
    for _ in $(seq 1 100); do
        [ -e "${BATS_TEST_TMPDIR}/copiando" ] && break
        sleep 0.1
    done
    [ -e "${BATS_TEST_TMPDIR}/copiando" ] || { kill "$pid"; skip 'la copia no empezó a tiempo'; }
    kill -TERM "$pid"
    wait "$pid" || rc=$?
    [ "$rc" -eq 143 ]
    grep -q 'Interrupción recibida (señal)' "$out"
    grep -q "ADVERTENCIA: la copia de seguridad quedó INCOMPLETA en: ${DEST}/backup_datos_" "$out"
}

# ---------------------------------------------------------------------------
# Cases that require root (mounts)
# ---------------------------------------------------------------------------

@test "opción 5 (root): espacio insuficiente en el destino" {
    require_root
    mount_tmpfs "${BATS_TEST_TMPDIR}/qa_small"
    head -c 6000000 /dev/zero >"${SRC}/grande"
    backup "${SRC}" "${BATS_TEST_TMPDIR}/qa_small"
    [[ "$output" == *"Espacio requerido (du -sb):"* ]]
    [[ "$output" == *"ERROR: espacio insuficiente en el destino."* ]]
    [ -z "$(ls -A "${BATS_TEST_TMPDIR}/qa_small")" ]
}

@test "opción 5 (root): destino montado como solo lectura" {
    require_root
    mount_tmpfs "${BATS_TEST_TMPDIR}/qa_ro"
    mount -o remount,ro "${BATS_TEST_TMPDIR}/qa_ro"
    backup "${SRC}" "${BATS_TEST_TMPDIR}/qa_ro"
    [[ "$output" == *"no tiene permiso de escritura en '${BATS_TEST_TMPDIR}/qa_ro' (o está montado como solo lectura)"* ]]
}

@test "opción 5 (root): destino vfat usa rsync -rt y advierte FAT" {
    require_root
    require_cmd mkfs.vfat rsync
    local img="${BATS_TEST_TMPDIR}/qa_vfat.img" mnt="${BATS_TEST_TMPDIR}/qa_vfat"
    truncate -s 64M "$img"
    mkfs.vfat "$img" >/dev/null
    mkdir -p "$mnt"
    mount -o loop,uid=1000,utf8 "$img" "$mnt"
    CLEANUP_MOUNTS+=("$mnt")
    backup "${SRC}" "$mnt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(sistema de archivos: vfat)"* ]]
    [[ "$output" == *"ADVERTENCIA: destino FAT: no se conservan propietarios, permisos ni enlaces simbólicos."* ]]
    [ "$(summary_field 'Método:')" = "rsync -rt --modify-window=2" ]
    [[ "$output" == *"EXITOSA"* ]]
    diff -r "${SRC}" "$(summary_field 'Copia de archivos:')"
}

@test "opción 5 (root): USB simulada (loop + lsblk falso) se elige con '1'" {
    require_root
    require_cmd mkfs.ext4 losetup
    make_loop_ext4 "${BATS_TEST_TMPDIR}/qa_usb.img"
    local mnt="${BATS_TEST_TMPDIR}/qa_usb"
    mount_loop "${LOOP_DEV}" "$mnt"
    export QA_DEV="${LOOP_DEV}"
    make_stub_dir
    make_stub lsblk <<'EOF'
case " $* " in
*" -dnpr "*) printf '%s disk 1 1 usb\n' "$QA_DEV" ;;
*" -npr "*) printf '%s 16M\n' "$QA_DEV" ;;
*) exec /usr/bin/lsblk "$@" ;;
esac
EOF
    PATH="${STUB_DIR}:${PATH}" run_tool 5 "${SRC}" 1 s '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"1) ${LOOP_DEV} (16M) montado en ${mnt}"* ]]
    [[ "$output" == *"EXITOSA"* ]]
    [[ "$output" == *"umount \"${mnt}\""* ]]
    diff -r "${SRC}" "$(summary_field 'Copia de archivos:')"
}
