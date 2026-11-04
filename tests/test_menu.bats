#!/usr/bin/env bats
#
# Main menu: option validation, exit with 0, EOF, dependencies,
# signals and cleanup of temporary files.

load test_helper

@test "menú: muestra las opciones 0-5 y sale con 0" {
    run_tool 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"1) Usuarios y último inicio de sesión"* ]]
    [[ "$output" == *"2) Sistemas de archivos y discos"* ]]
    [[ "$output" == *"3) Los diez archivos más grandes"* ]]
    [[ "$output" == *"4) Memoria RAM y swap"* ]]
    [[ "$output" == *"5) Copia de seguridad a USB"* ]]
    [[ "$output" == *"0) Salir"* ]]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "menú: EOF en stdin termina el ciclo con código 0" {
    run_tool
    [ "$status" -eq 0 ]
    # The menu is drawn exactly once: there is no infinite loop.
    [ "$(grep -c '0) Salir' <<<"$output")" -eq 1 ]
}

@test "menú: EOF después de una opción inválida también termina con 0" {
    run_tool x
    [ "$status" -eq 0 ]
    [[ "$output" == *"opción no válida: 'x'"* ]]
}

@test "menú: letras producen error en español y el menú continúa" {
    run_tool abc '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: opción no válida: 'abc'. Ingrese un número entre 0 y 5."* ]]
    [ "$(grep -c '0) Salir' <<<"$output")" -eq 2 ]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "menú: número fuera de rango (9) produce error" {
    run_tool 9 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"opción no válida: '9'"* ]]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "menú: número negativo (-1) produce error" {
    run_tool -1 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"opción no válida: '-1'"* ]]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "menú: entrada vacía produce error" {
    run_tool '' '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"opción no válida: ''"* ]]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "menú: '00', '1a' y '10' no se aceptan como opciones válidas" {
    run_tool 00 '' 1a '' 10 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"opción no válida: '00'"* ]]
    [[ "$output" == *"opción no válida: '1a'"* ]]
    [[ "$output" == *"opción no válida: '10'"* ]]
}

@test "menú: varios errores seguidos no rompen el ciclo" {
    run_tool a '' b '' c '' 0
    [ "$status" -eq 0 ]
    [ "$(grep -c 'opción no válida' <<<"$output")" -eq 3 ]
    [ "$(grep -c '0) Salir' <<<"$output")" -eq 4 ]
}

@test "menú: los mensajes de error van a stderr, no a stdout" {
    run_tool_stdout zz '' 0
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"opción no válida: 'zz'"* ]]
    [[ "$output" != *"opción no válida"* ]]
}

@test "menú: sin TTY no se imprimen prompts ni secuencias de escape" {
    run_tool_stdout 0
    [ "$status" -eq 0 ]
    [[ "$output" != *"Seleccione una opción:"* ]]
    [[ "$output" != *$'\e['* ]]
}

@test "menú: advierte cuando no se ejecuta como root" {
    require_non_root
    run_tool 0
    [[ "$output" == *"ADVERTENCIA: no se está ejecutando como root"* ]]
}

@test "menú: como root no muestra la advertencia de privilegios" {
    require_root
    run_tool 0
    [[ "$output" != *"no se está ejecutando como root"* ]]
}

@test "arranque: falta de comandos obligatorios termina con código 1" {
    make_min_path
    rm -f "${MIN_PATH}/findmnt" "${MIN_PATH}/lsblk"
    PATH="${MIN_PATH}" run "${MIN_PATH}/bash" "${TOOL}" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"faltan comandos obligatorios: findmnt lsblk"* ]]
}

@test "señales: SIGTERM termina con código 143 y mensaje de interrupción" {
    local out="${BATS_TEST_TMPDIR}/sig.out" pid rc=0
    bash "${TOOL}" < <(sleep 30) >"${out}" 2>&1 &
    pid=$!
    sleep 1
    kill -TERM "${pid}"
    wait "${pid}" || rc=$?
    [ "${rc}" -eq 143 ]
    grep -q 'Interrupción recibida (señal). Saliendo...' "${out}"
}

@test "limpieza: no quedan archivos temporales tras usar la opción 3" {
    local tmp data
    tmp="$(make_temp_dir tmpdir)"
    data="$(make_temp_dir data)"
    printf 'x' >"${data}/f"
    TMPDIR="${tmp}" run_tool 3 "${data}" '' 0
    [ "$status" -eq 0 ]
    run ls -A "${tmp}"
    [ -z "$output" ]
}

@test "limpieza: no quedan /tmp/tmp.* nuevos tras la opción 3 (TMPDIR por defecto)" {
    local data before after
    data="$(make_temp_dir data)"
    printf 'x' >"${data}/f"
    before="$(find /tmp -maxdepth 1 -name 'tmp.*' -user "$(id -u)" 2>/dev/null | sort)"
    env -u TMPDIR bash "${TOOL}" < <(printf '3\n%s\n\n0\n' "${data}") >/dev/null 2>&1
    after="$(find /tmp -maxdepth 1 -name 'tmp.*' -user "$(id -u)" 2>/dev/null | sort)"
    [ "$(comm -13 <(echo "$before") <(echo "$after") | grep -c .)" -eq 0 ]
}
