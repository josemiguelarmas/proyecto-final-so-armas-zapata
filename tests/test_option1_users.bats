#!/usr/bin/env bats
# shellcheck disable=SC2016  # code inside single quotes is evaluated in run_fn
#
# Option 1: users (getent passwd), human/system classification and last
# login (lastlog2 -> lastlog -> last). External binaries are replaced by
# stubs in PATH so the analysis is deterministic.

load test_helper

setup() {
    export TZ=UTC
    make_stub_dir
}

# getent stub with a controlled passwd.
stub_getent() {
    make_stub getent <<'EOF'
if [ "$1" = passwd ]; then
cat <<'PW'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
sshd:x:999:65534::/run/sshd:/usr/sbin/nologin
alice:x:1000:1000::/home/alice:/bin/bash
bob:x:1001:1001::/home/bob:/bin/bash
carol:x:60000:60000::/home/carol:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
PW
else
exec /usr/bin/getent "$@"
fi
EOF
}

# lastlog2/lastlog stub with the real format (Username Port From Latest).
# $1 = stub name.
stub_lastlog() {
    make_stub "$1" <<'EOF'
[ "$1" = -u ] || exit 2
printf 'Username         Port     From                                       Latest\n'
case "$2" in
root)  printf 'root             pts/0    10.0.0.5                                   Tue Nov  3 16:08:53 +0000 2026\n' ;;
alice) printf 'alice                                                               Mon Oct  5 08:01:02 +0000 2026\n' ;;
bob)   printf 'bob                                                                 **Never logged in**\n' ;;
carol) printf 'carol            tty1                                                Sun Feb  1 23:59:59 +0000 2026\n' ;;
*)     printf '%-16s %53s\n' "$2" '**Never logged in**' ;;
esac
EOF
}

# last (wtmpdb) stub with --time-format iso output.
stub_last() {
    make_stub last <<'EOF'
user="${@: -1}"
case "$user" in
root)  printf 'root     pts/0        10.0.0.5         2026-11-03T16:08:53+0000 - 2026-11-03T17:00:00+0000  (00:51)\n\nwtmpdb begins 2026-01-01T00:00:00+0000\n' ;;
alice) printf 'alice    tty1                          2026-10-05T08:01:02-0500   still logged in\n\nwtmpdb begins 2026-01-01T00:00:00+0000\n' ;;
*)     printf '\nwtmpdb begins 2026-01-01T00:00:00+0000\n' ;;
esac
EOF
}

# ---------------------------------------------------------------------------
# Unit: is_human_uid
# ---------------------------------------------------------------------------

@test "is_human_uid: root (0) y UID >= 1000 son humanos" {
    run_fn 'is_human_uid 0 && is_human_uid 1000 && is_human_uid 1001 && is_human_uid 60000'
    [ "$status" -eq 0 ]
}

@test "is_human_uid: UID 1-999 y nobody (65534) son de sistema" {
    run_fn 'for u in 1 100 999 65534; do is_human_uid "$u" && exit 1; done; exit 0'
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Unit: lastlog / lastlog2 parsing
# ---------------------------------------------------------------------------

@test "lastlog: línea con Port y From extrae fecha y hora" {
    stub_lastlog lastlog2
    run_fn "LOGIN_TOOL_NAME=lastlog2 LOGIN_TOOL_PATH='${STUB_DIR}/lastlog2'; get_last_login root"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-11-03 16:08:53" ]
}

@test "lastlog: Port y From vacíos no desplazan las columnas" {
    stub_lastlog lastlog
    run_fn "LOGIN_TOOL_NAME=lastlog LOGIN_TOOL_PATH='${STUB_DIR}/lastlog'; get_last_login alice"
    [ "$output" = "2026-10-05 08:01:02" ]
}

@test "lastlog: solo Port (sin From) también se interpreta" {
    stub_lastlog lastlog
    run_fn "LOGIN_TOOL_NAME=lastlog LOGIN_TOOL_PATH='${STUB_DIR}/lastlog'; get_last_login carol"
    [ "$output" = "2026-02-01 23:59:59" ]
}

@test "lastlog: '**Never logged in**' se reporta como NEVER" {
    stub_lastlog lastlog2
    run_fn "LOGIN_TOOL_NAME=lastlog2 LOGIN_TOOL_PATH='${STUB_DIR}/lastlog2'; get_last_login bob"
    [ "$output" = "NEVER" ]
}

@test "lastlog: herramienta sin datos (solo cabecera) es UNAVAILABLE" {
    make_stub lastlog2 <<'EOF'
printf 'Username         Port     From             Latest\n'
EOF
    run_fn "LOGIN_TOOL_NAME=lastlog2 LOGIN_TOOL_PATH='${STUB_DIR}/lastlog2'; get_last_login x"
    [ "$output" = "UNAVAILABLE" ]
}

@test "lastlog: herramienta que falla sin salida es UNAVAILABLE" {
    make_stub lastlog2 <<'EOF'
echo "lastlog2: error" >&2; exit 1
EOF
    run_fn "LOGIN_TOOL_NAME=lastlog2 LOGIN_TOOL_PATH='${STUB_DIR}/lastlog2'; get_last_login x"
    [ "$output" = "UNAVAILABLE" ]
}

@test "lastlog: fecha ilegible es UNAVAILABLE" {
    make_stub lastlog2 <<'EOF'
printf 'Username Port From Latest\nzed  a b c d e\n'
EOF
    run_fn "LOGIN_TOOL_NAME=lastlog2 LOGIN_TOOL_PATH='${STUB_DIR}/lastlog2'; get_last_login zed"
    [ "$output" = "UNAVAILABLE" ]
}

@test "lastlog: se invoca con LC_ALL=C y '-u usuario'" {
    make_stub lastlog2 <<EOF
printf '%s|%s\n' "\${LC_ALL:-}" "\$*" >"${BATS_TEST_TMPDIR}/args"
printf 'h\nu **Never logged in**\n'
EOF
    run_fn "LOGIN_TOOL_NAME=lastlog2 LOGIN_TOOL_PATH='${STUB_DIR}/lastlog2'; get_last_login 'usr'"
    [ "$output" = "NEVER" ]
    [ "$(cat "${BATS_TEST_TMPDIR}/args")" = "C|-u usr" ]
}

# ---------------------------------------------------------------------------
# Unit: last (wtmp / wtmpdb) parsing
# ---------------------------------------------------------------------------

@test "last: salida ISO con sesión cerrada extrae fecha y hora" {
    stub_last
    run_fn "LOGIN_TOOL_NAME=last LOGIN_TOOL_PATH='${STUB_DIR}/last'; get_last_login root"
    [ "$output" = "2026-11-03 16:08:53" ]
}

@test "last: sesión activa ('still logged in') extrae fecha y hora" {
    stub_last
    run_fn "LOGIN_TOOL_NAME=last LOGIN_TOOL_PATH='${STUB_DIR}/last'; get_last_login alice"
    [ "$output" = "2026-10-05 08:01:02" ]
}

@test "last: solo 'wtmpdb begins' (sin registros) es NEVER" {
    stub_last
    run_fn "LOGIN_TOOL_NAME=last LOGIN_TOOL_PATH='${STUB_DIR}/last'; get_last_login bob"
    [ "$output" = "NEVER" ]
}

@test "last: formato clásico 'wtmp begins' sin registros es NEVER" {
    make_stub last <<'EOF'
printf '\nwtmp begins Sun Nov  1 00:00:00 2026\n'
EOF
    run_fn "LOGIN_TOOL_NAME=last LOGIN_TOOL_PATH='${STUB_DIR}/last'; get_last_login bob"
    [ "$output" = "NEVER" ]
}

@test "last: código de salida distinto de 0 es UNAVAILABLE" {
    make_stub last <<'EOF'
echo "last: cannot open /var/log/wtmp" >&2; exit 1
EOF
    run_fn "LOGIN_TOOL_NAME=last LOGIN_TOOL_PATH='${STUB_DIR}/last'; get_last_login bob"
    [ "$output" = "UNAVAILABLE" ]
}

@test "last: se invoca con --time-format iso -n 1 usuario" {
    make_stub last <<EOF
printf '%s\n' "\$*" >"${BATS_TEST_TMPDIR}/args"
printf '\nwtmpdb begins x\n'
EOF
    run_fn "LOGIN_TOOL_NAME=last LOGIN_TOOL_PATH='${STUB_DIR}/last'; get_last_login ana"
    [ "$(cat "${BATS_TEST_TMPDIR}/args")" = "--time-format iso -n 1 ana" ]
}

@test "get_last_login: sin herramienta detectada es UNAVAILABLE" {
    run_fn "LOGIN_TOOL_NAME=''; get_last_login root"
    [ "$output" = "UNAVAILABLE" ]
}

# ---------------------------------------------------------------------------
# Unit: lastlog2 -> lastlog -> last detection chain
# ---------------------------------------------------------------------------

@test "detección: prefiere lastlog2 cuando existen las tres" {
    make_min_path
    stub_lastlog lastlog2; stub_lastlog lastlog; stub_last
    PATH="${STUB_DIR}:${MIN_PATH}" run_fn 'detect_login_tool; echo "$LOGIN_TOOL_NAME $LOGIN_TOOL_PATH"'
    [ "$output" = "lastlog2 ${STUB_DIR}/lastlog2" ]
}

@test "detección: usa lastlog si no hay lastlog2" {
    make_min_path
    stub_lastlog lastlog; stub_last
    [ -x /usr/sbin/lastlog2 ] && skip 'lastlog2 existe en /usr/sbin'
    PATH="${STUB_DIR}:${MIN_PATH}" run_fn 'detect_login_tool; echo "$LOGIN_TOOL_NAME"'
    [ "$output" = "lastlog" ]
}

@test "detección: usa last si no hay lastlog2 ni lastlog" {
    make_min_path
    stub_last
    [ -x /usr/sbin/lastlog2 ] || [ -x /usr/sbin/lastlog ] && skip 'lastlog/lastlog2 existe en /usr/sbin'
    PATH="${STUB_DIR}:${MIN_PATH}" run_fn 'detect_login_tool; echo "$LOGIN_TOOL_NAME"'
    [ "$output" = "last" ]
}

@test "detección: busca también en /usr/sbin aunque no esté en PATH" {
    local found=''
    for t in lastlog2 lastlog last; do
        [ -x "/usr/sbin/$t" ] && { found="$t"; break; }
    done
    [ -n "$found" ] || skip 'no hay herramientas de login en /usr/sbin'
    make_min_path
    PATH="${MIN_PATH}" run_fn 'detect_login_tool; echo "$LOGIN_TOOL_PATH"'
    [ "$output" = "/usr/sbin/$found" ]
}

@test "detección: sin ninguna herramienta devuelve error" {
    for t in lastlog2 lastlog last; do
        [ -x "/usr/sbin/$t" ] && skip "existe /usr/sbin/$t"
    done
    make_min_path
    PATH="${MIN_PATH}" run_fn 'detect_login_tool'
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Integration: complete option 1 with stubs
# ---------------------------------------------------------------------------

@test "opción 1 / 1: solo humanos (root, UID>=1000, sin nobody)" {
    stub_getent; stub_lastlog lastlog2
    PATH="${STUB_DIR}:${PATH}" run_tool 1 1 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fuente del último inicio de sesión: ${STUB_DIR}/lastlog2"* ]]
    [[ "$output" == *"USUARIOS HUMANOS (4)"* ]]
    [[ "$output" != *"CUENTAS DE SISTEMA"* ]]
    [[ "$output" != *nobody* ]]
    [[ "$output" != *daemon* ]]
    [[ "$output" != *sshd* ]]
}

@test "opción 1 / 1: columnas USUARIO UID FECHA HORA con valores correctos" {
    stub_getent; stub_lastlog lastlog2
    PATH="${STUB_DIR}:${PATH}" run_tool 1 1 '' 0
    grep -Eq '^USUARIO +UID  FECHA +HORA' <<<"$output"
    # Fixed width: USUARIO takes 24 columns and UID is right-aligned
    # in the next 8 (positions 25-32).
    local line rows
    line="$(grep -E '^USUARIO ' <<<"$output")"
    [ "${line:30:3}" = "UID" ]
    rows="$(grep -E '^(root|alice|bob|carol) ' <<<"$output")"
    while IFS= read -r line; do
        [[ "${line:25:8}" =~ ^\ *[0-9]+$ ]]
        [ "${line:33:2}" = "  " ]
    done <<<"$rows"
    grep -Eq '^root +0  2026-11-03 16:08:53$' <<<"$output"
    grep -Eq '^alice +1000  2026-10-05 08:01:02$' <<<"$output"
    grep -Eq '^carol +60000  2026-02-01 23:59:59$' <<<"$output"
    grep -Eq '^bob +1001  Nunca ha iniciado sesión$' <<<"$output"
}

@test "opción 1 / 2: todas las cuentas; nobody y UID<1000 en sistema" {
    stub_getent; stub_lastlog lastlog2
    PATH="${STUB_DIR}:${PATH}" run_tool 1 2 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"USUARIOS HUMANOS (4)"* ]]
    [[ "$output" == *"CUENTAS DE SISTEMA (3)"* ]]
    local system
    system="$(sed -n '/CUENTAS DE SISTEMA/,$p' <<<"$output")"
    grep -Eq '^nobody +65534  Nunca ha iniciado sesión$' <<<"$system"
    grep -Eq '^daemon +1  ' <<<"$system"
    grep -Eq '^sshd +999  ' <<<"$system"
}

@test "opción 1: con last (wtmpdb) muestra fecha y 'Nunca ha iniciado sesión'" {
    make_min_path
    stub_getent; stub_last
    [ -x /usr/sbin/lastlog2 ] || [ -x /usr/sbin/lastlog ] && skip 'lastlog/lastlog2 existe en /usr/sbin'
    PATH="${STUB_DIR}:${MIN_PATH}" run "${MIN_PATH}/bash" "${TOOL}" < <(printf '1\n1\n\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fuente del último inicio de sesión: ${STUB_DIR}/last"* ]]
    grep -Eq '^root +0  2026-11-03 16:08:53$' <<<"$output"
    grep -Eq '^bob +1001  Nunca ha iniciado sesión$' <<<"$output"
}

@test "opción 1: sin herramientas de login muestra advertencia y 'No disponible'" {
    for t in lastlog2 lastlog last; do
        [ -x "/usr/sbin/$t" ] && skip "existe /usr/sbin/$t"
    done
    make_min_path
    stub_getent
    PATH="${STUB_DIR}:${MIN_PATH}" run "${MIN_PATH}/bash" "${TOOL}" < <(printf '1\n1\n\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA: no se encontró lastlog2, lastlog ni last"* ]]
    grep -Eq '^root +0  No disponible$' <<<"$output"
    grep -Eq '^alice +1000  No disponible$' <<<"$output"
}

@test "opción 1: subopción inválida muestra error y vuelve al menú" {
    run_tool 1 3 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: opción no válida: '3'."* ]]
    [[ "$output" == *"Hasta luego."* ]]
}

@test "opción 1: subopción vacía muestra error" {
    run_tool 1 '' '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: opción no válida: ''."* ]]
}

# ---------------------------------------------------------------------------
# Integration with the real system (WSL/Ubuntu with lastlog2 + wtmpdb)
# ---------------------------------------------------------------------------

@test "sistema real: cuentas humanas de getent aparecen todas" {
    local expected
    expected="$(getent passwd | awk -F: '$3 == 0 || ($3 >= 1000 && $3 != 65534)' | wc -l)"
    run_tool 1 1 '' 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"USUARIOS HUMANOS (${expected})"* ]]
}

@test "sistema real: usuario sin inicio de sesión muestra 'Nunca ha iniciado sesión'" {
    getent passwd ana >/dev/null || skip 'no existe el usuario ana'
    run_tool 1 1 '' 0
    grep -Eq '^ana +1001  Nunca ha iniciado sesión$' <<<"$output"
}

@test "sistema real: usuario con inicio de sesión muestra fecha y hora" {
    getent passwd jarma >/dev/null || skip 'no existe el usuario jarma'
    unset TZ
    run_tool 1 1 '' 0
    grep -Eq '^jarma +1000  [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' <<<"$output"
}
