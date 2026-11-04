# Opción 1 — Usuarios y último inicio de sesión

## Requisito

> Desplegar los usuarios creados en el sistema, y la fecha y hora de su último
> ingreso (login).

## Comandos y archivos usados, y por qué

| Recurso | Uso | Alternativas descartadas |
|---|---|---|
| `getent passwd` | Lista de cuentas (`usuario:x:UID:GID:…`) | **Leer `/etc/passwd`**: solo ve cuentas locales. `getent` consulta las fuentes de `/etc/nsswitch.conf` (archivos, LDAP, NIS, SSSD), que es lo que ve el sistema realmente en un data center. |
| `lastlog2 -u USER` | Último login (util-linux; base SQLite `/var/lib/lastlog/lastlog2.db`) | — Es la herramienta actual en Debian 13, Ubuntu 25.04+ y Fedora. |
| `lastlog -u USER` | Último login (shadow-utils; archivo `/var/log/lastlog`) | Obsoleta (problema del año 2038), pero es la que trae RHEL/Rocky 9. |
| `last --time-format iso -n 1 USER` | Última sesión en `wtmp` (util-linux o `wtmpdb`) | Recurso final: `wtmp` se rota, así que puede "olvidar" logins antiguos. |
| `date -d` | Normaliza la fecha de `lastlog*` a `AAAA-MM-DD HH:MM:SS` | Mostrar el texto crudo: formato distinto en cada herramienta. |

**Por qué detectar en tiempo de ejecución** (`detect_login_tool`): ninguna
herramienta existe en todas las distribuciones (ver tabla de diferencias). El
orden `lastlog2 → lastlog → last` va de la fuente más precisa y moderna a la
más genérica. El script imprime cuál usó
(`Fuente del último inicio de sesión: …`) para que el resultado sea auditable.

**Por qué `find_command` busca también en `/usr/sbin` y `/sbin`**: en
Fedora/RHEL `lastlog2` está en `/usr/sbin`, que no suele estar en el `PATH`
de un usuario normal; `command -v` no la encontraría.

**Por qué `LC_ALL=C`** al ejecutar `lastlog*`, `last` y `date`: el texto
`**Never logged in**` y los nombres de mes/día se traducen según el idioma;
con la configuración C el formato es fijo y parseable.

## Algoritmo

1. `option_users` muestra el submenú: `1` solo humanos, `2` todas las
   cuentas. Otra entrada → `ERROR: opción no válida: '…'.`
2. `detect_login_tool` prueba `lastlog2`, `lastlog`, `last` con
   `find_command` y guarda `LOGIN_TOOL_NAME`/`LOGIN_TOOL_PATH`. Si no hay
   ninguna, dos advertencias (instalar `lastlog2` en Debian/Ubuntu o
   `util-linux` en Fedora/RHEL) y se sigue: la columna mostrará "No
   disponible".
3. Lee `getent passwd` con `while IFS=: read -r user _ uid _` (separa por `:`;
   `_` descarta campos) y clasifica con `is_human_uid`:
   `uid == 0 || (uid >= 1000 && uid != 65534)`.
4. `print_users_table` imprime "USUARIOS HUMANOS (N)" y, con la opción 2,
   "CUENTAS DE SISTEMA (N)". Para cada cuenta llama a `get_last_login`, que
   devuelve `AAAA-MM-DD HH:MM:SS`, `NEVER` o `UNAVAILABLE`:
   - `login_from_lastlog`: toma la línea 2 de `lastlog* -u USER` (la 1 es el
     encabezado). Si contiene `**Never logged in**` → `NEVER`. Si no, toma
     los **últimos cinco campos** (`$(NF-4)…$NF`, p. ej.
     `Nov 3 16:08:53 +0000 2026`) porque las columnas *Port* y *From* pueden
     estar vacías y desplazar las posiciones fijas; los pasa a `date -d`.
     Salida vacía o fecha no parseable → `UNAVAILABLE`.
   - `login_from_last`: toma la primera línea de
     `last --time-format iso -n 1 USER` y busca el campo que coincide con
     `^AAAA-MM-DDTHH:MM:SS` (`BASH_REMATCH`). Sin coincidencia (solo aparece
     "wtmp begins …") → `NEVER`. Si `last` falla → `UNAVAILABLE`.
5. Se traduce: `NEVER` → "Nunca ha iniciado sesión", `UNAVAILABLE` → "No
   disponible"; si hay fecha se separa en columnas FECHA y HORA.

Las cuentas se muestran en el orden de `getent` (el de `/etc/passwd`).

## Permisos

- `getent passwd` es legible por cualquier usuario (no contiene contraseñas;
  esas están en `/etc/shadow`).
- `/var/log/lastlog`, `lastlog2.db` y `wtmp` normalmente son legibles por
  todos; la opción funciona sin root. En el ejemplo real se ejecutó como
  usuario normal.

## Casos borde

| Caso | Comportamiento |
|---|---|
| Ninguna herramienta de login instalada | Advertencias + "No disponible" en todas las filas |
| `lastlog` sin `/var/log/lastlog` (Rocky 9 en contenedor) | "No disponible" |
| Usuario que nunca inició sesión | "Nunca ha iniciado sesión" |
| Columnas *Port*/*From* vacías en `lastlog2` | Se usan los últimos 5 campos, no posiciones fijas |
| Sesión activa en `last` ("still logged in") | Se toma el primer campo ISO (hora de inicio) |
| `wtmp` rotado | `last` no encuentra la sesión → "Nunca ha iniciado sesión" |
| `nobody` (UID 65534) | Se clasifica como cuenta de sistema |
| Lista de sistema vacía | `print_users_table` imprime "(0)"; no falla con `set -u` gracias a bash ≥ 4.4 |

## Diferencias entre distribuciones (verificado)

| Distribución | Herramienta encontrada |
|---|---|
| Ubuntu 26.04 (WSL) por defecto | Ninguna → "No disponible" + sugerencia (paquete `lastlog2`) |
| Ubuntu 26.04 con `lastlog2` | `/usr/bin/lastlog2` |
| Ubuntu 26.04 solo con `wtmpdb` | `last --time-format iso` |
| Debian 13 | `lastlog2` (paquete `lastlog2`) |
| Fedora 45 | `/usr/sbin/lastlog2` |
| Rocky Linux 9.3 | `lastlog` (shadow-utils) |

## Ejemplo real

WSL Ubuntu 26.04 con `lastlog2`, usuario normal. Entrada: `1`, `2` (todas las
cuentas). Lista recortada con `…`.

```text
=== Usuarios del sistema y último inicio de sesión ===

  1) Solo usuarios humanos (root y UID >= 1000)
  2) Todas las cuentas (humanas y de sistema)

Fuente del último inicio de sesión: /usr/bin/lastlog2

USUARIOS HUMANOS (3)
USUARIO                       UID  FECHA      HORA    
-------                       ---  -----      ----    
root                            0  Nunca ha iniciado sesión
jarma                        1000  2026-11-03 17:47:38
ana                          1001  Nunca ha iniciado sesión

CUENTAS DE SISTEMA (25)
USUARIO                       UID  FECHA      HORA    
-------                       ---  -----      ----    
daemon                          1  Nunca ha iniciado sesión
bin                             2  Nunca ha iniciado sesión
sys                             3  Nunca ha iniciado sesión
…
nobody                      65534  Nunca ha iniciado sesión
systemd-network               998  Nunca ha iniciado sesión
…
polkitd                       987  Nunca ha iniciado sesión
```

Con la entrada `1`, `1` se imprime solo la sección "USUARIOS HUMANOS (3)".

## Limitaciones

- Depende de la herramienta instalada y de que su base de datos exista.
- `lastlog2`/`lastlog` guardan solo el **último** login por usuario; `last`
  depende de que `wtmp` no se haya rotado.
- La heurística de humano no lee `UID_MIN` de `/etc/login.defs` (hay sistemas
  con `UID_MIN=500`).

## Preguntas probables de la sustentación

**¿Por qué `getent passwd` y no `cat /etc/passwd`?**
`getent` respeta `/etc/nsswitch.conf`: devuelve también usuarios de LDAP/NIS/SSSD.
En un servidor unido a un directorio, `/etc/passwd` solo tendría las cuentas
locales.

**¿Cómo distinguen un usuario humano de una cuenta de sistema?**
Por UID: root (0) y UID ≥ 1000, excepto `nobody` (65534). Es la convención de
`useradd` (`UID_MIN=1000` en `/etc/login.defs`). Limitación: no leemos ese
archivo.

**¿De dónde sale la fecha del último login?**
De `lastlog2` (base SQLite que escribe el módulo PAM `pam_lastlog2` al iniciar
sesión), de `lastlog` (`/var/log/lastlog`, indexado por UID) o de `last`
(registro histórico `wtmp`). Se usa la primera disponible y se muestra cuál.

**¿Por qué no usar posiciones fijas de columna al parsear `lastlog`?**
Port y From pueden estar vacíos (login local), y `awk` colapsa espacios, así
que el número de campos varía. Los últimos cinco campos siempre son la fecha.

**¿Qué pasa si `lastlog2` no está en el PATH?**
`find_command` también busca en `/usr/sbin` y `/sbin`; así se encontró en
Fedora como usuario normal.

**¿Por qué `LC_ALL=C`?**
Para que `**Never logged in**` y los nombres de meses no se traduzcan y el
parseo no dependa del idioma del sistema.
