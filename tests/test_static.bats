#!/usr/bin/env bats
#
# Static checks of the script: ShellCheck, syntax, shebang,
# execute permissions and line endings.

load test_helper

@test "estático: shellcheck no reporta ningún hallazgo" {
    require_cmd shellcheck
    run shellcheck "${TOOL}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "estático: bash -n no encuentra errores de sintaxis" {
    run bash -n "${TOOL}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "estático: la primera línea es '#!/usr/bin/env bash'" {
    [ "$(head -n 1 "${TOOL}")" = '#!/usr/bin/env bash' ]
}

@test "estático: el script tiene bit de ejecución (git y sistema de archivos)" {
    [ -x "${TOOL}" ]
    if command -v git >/dev/null 2>&1 &&
        git -c safe.directory='*' -C "${REPO_ROOT}" rev-parse >/dev/null 2>&1; then
        run git -c safe.directory='*' -C "${REPO_ROOT}" ls-files -s -- bash/sysadmin-tool.sh
        [[ "$output" == 100755* ]]
    fi
}

@test "estático: no contiene finales de línea CRLF" {
    [ "$(grep -c $'\r' "${TOOL}")" -eq 0 ]
}

@test "estático: los archivos de pruebas tampoco contienen CRLF" {
    local f
    for f in "${TESTS_DIR}"/*.bats "${TESTS_DIR}"/*.bash "${TESTS_DIR}"/*.sh; do
        [ -e "$f" ] || continue
        [ "$(grep -c $'\r' "$f")" -eq 0 ]
    done
}

@test "estático: al cargarse con source no ejecuta el menú" {
    run bash -c 'source "$1" </dev/null; echo "cargado"' _ "${TOOL}"
    [ "$status" -eq 0 ]
    [ "$output" = "cargado" ]
}

@test "estático: run-tests.sh existe y es ejecutable" {
    [ -x "${TESTS_DIR}/run-tests.sh" ]
    [ "$(head -n 1 "${TESTS_DIR}/run-tests.sh")" = '#!/usr/bin/env bash' ]
}
