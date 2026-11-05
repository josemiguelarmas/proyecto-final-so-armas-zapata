# Arquitectura de `bash/sysadmin-tool.sh`

Un único script (~940 líneas), sin archivos auxiliares. Textos al usuario en
español; identificadores y comentarios en inglés.

## 1. Secciones del script

| Orden | Sección | Contenido |
|---|---|---|
| 1 | Cabecera y opciones de shell | `#!/usr/bin/env bash`, `set -uo pipefail` |
| 2 | Constantes y estado global | `readonly …`, variables de estado |
| 3 | *Generic helpers* | Mensajes, entrada, formato |
| 4 | *Startup checks* | `check_dependencies` |
| 5 | *Option 1* … *Option 5* | Una sección por opción del menú |
| 6 | *Menu and entry point* | Traps, menú, `main` |
| 7 | Guarda de ejecución | `main` solo si el archivo se ejecuta (no si se hace `source`) |

`#!/usr/bin/env bash` busca bash en el `PATH` en lugar de fijar `/bin/bash`
(más portable, p. ej. si bash está en `/usr/local/bin`).

## 2. Variables globales

Constantes (`readonly`):

| Nombre | Valor | Uso |
|---|---|---|
| `SCRIPT_NAME` | `${0##*/}` | Nombre en mensajes de error |
| `REQUIRED_CMDS` | `getent df find sort head tail tr wc awk du date mktemp basename sync findmnt lsblk` | Verificadas al inicio |
| `SBIN_DIRS` | `/usr/sbin /sbin` | Búsqueda extra de `lastlog2`/`lastlog`/`last` (fuera del `PATH` de un usuario normal en Fedora/RHEL) |
| `HUMAN_UID_MIN` | `1000` | Umbral de usuario humano |
| `NOBODY_UID` | `65534` | `nobody` se considera cuenta de sistema |
| `PSEUDO_FS_TYPES` | `tmpfs devtmpfs squashfs overlay efivarfs ramfs rootfs proc sysfs devpts cgroup cgroup2 autofs` | Tipos ocultos por defecto en la opción 2 |

Estado mutable (las funciones de bash no pueden devolver arreglos ni varias
cadenas, así que los resultados compuestos se dejan en globales):

| Nombre | Escrita por | Significado |
|---|---|---|
| `LOGIN_TOOL_NAME`, `LOGIN_TOOL_PATH` | `detect_login_tool` | Herramienta de último login elegida |
| `USB_TARGETS`, `USB_LABELS` | `find_usb_mount_points` | Puntos de montaje USB y su descripción |
| `SELECTED_DEST` | `select_destination` | Destino elegido en la opción 5 |
| `INPUT_PATH` | `read_path` | Ruta tecleada por el usuario |
| `COPY_METHOD` | `copy_tree` | Comando usado para copiar (se muestra en el resumen) |
| `CURRENT_BACKUP_DIR` | `run_backup` | No vacía mientras se escribe una copia; la usa `on_interrupt` |
| `TMP_FILES` | `option_largest_files` | Temporales que `cleanup` borra al salir |

## 3. Funciones

### Auxiliares genéricas

| Función | Propósito |
|---|---|
| `print_error` | `ERROR: …` por stderr |
| `print_warning` | `ADVERTENCIA: …` por stderr |
| `print_header` | Título `=== … ===` |
| `print_field` | Línea "etiqueta valor" con la etiqueta rellenada a 22 **caracteres** (usa `${#label}`; `printf %-22s` rellena por bytes y desalinea tildes) |
| `clear_screen` | `clear` solo si stdout es una terminal |
| `pause` | "Presione Enter para volver al menú..." |
| `is_root` | `EUID == 0` |
| `warn_if_not_root` | Advertencia si no es root |
| `read_path` | Lee una ruta con `IFS= read -r` (conserva espacios iniciales/finales y `\`) y expande `~` inicial |
| `confirm` | Pregunta s/N; éxito solo con `s`/`S`, si no imprime "Operación cancelada." |
| `human_size` | Bytes → IEC (`KiB`, `MiB`…) con `numfmt`; respaldo en `awk` |
| `percentage` | Porcentaje con 2 decimales en `awk`; `0.00` si el total es 0 |
| `check_dependencies` | Verifica `REQUIRED_CMDS` con `command -v` |

### Opción 1 — usuarios ([detalle](option-1-users.md))

| Función | Propósito |
|---|---|
| `find_command` | Ruta de un comando en `PATH` o en `SBIN_DIRS` |
| `detect_login_tool` | Elige `lastlog2`, `lastlog` o `last` |
| `login_from_lastlog` | Parsea `lastlog`/`lastlog2 -u USER` (últimos 5 campos) |
| `login_from_last` | Parsea `last --time-format iso -n 1 USER` |
| `get_last_login` | Despacha según `LOGIN_TOOL_NAME`; devuelve fecha, `NEVER` o `UNAVAILABLE` |
| `is_human_uid` | `uid == 0` o (`uid >= 1000` y `uid != 65534`) |
| `print_users_table` | Imprime una tabla USUARIO/UID/FECHA/HORA |
| `option_users` | Flujo de la opción 1 |

### Opción 2 — sistemas de archivos ([detalle](option-2-filesystems.md))

| Función | Propósito |
|---|---|
| `max_length` | Longitud máxima de sus argumentos (ancho de columnas) |
| `option_filesystems` | `df -B1 --output=…` + `lsblk -b` |

### Opción 3 — archivos más grandes ([detalle](option-3-largest-files.md))

| Función | Propósito |
|---|---|
| `resolve_search_path` | Dispositivo → punto de montaje (`findmnt`); directorio → ruta absoluta física |
| `option_largest_files` | `find -xdev … \0 \| sort -z -rn \| head -z -n 10` |

### Opción 4 — memoria ([detalle](option-4-memory.md))

| Función | Propósito |
|---|---|
| `print_memory_line` | Línea "etiqueta bytes legible porcentaje" |
| `option_memory` | Lee `/proc/meminfo` con `awk` |

### Opción 5 — copia de seguridad ([detalle](option-5-backup.md))

| Función | Propósito |
|---|---|
| `find_usb_mount_points` | Discos USB/removibles (`lsblk`) y sus montajes (`findmnt`) |
| `select_destination` | Menú de destinos: USB detectadas, `m` manual, `c` cancelar |
| `absolute_dir` | Ruta absoluta física (`cd -P` + `pwd -P` en subshell) |
| `validate_backup_source` | Existe, es directorio, legible y atravesable |
| `validate_backup_destination` | Montado, escribible, no dentro del origen; aviso si mismo FS |
| `check_free_space` | `du -sb` del origen vs. `df --output=avail` del destino |
| `is_fat_filesystem` | `vfat`, `msdos`, `fat`, `exfat` |
| `copy_tree` | `rsync` (o `cp`) con opciones según el FS destino |
| `write_catalog` | Genera `catalogo.txt` con `find -printf '%P\t%T…\0'` |
| `unique_backup_dir` | Agrega `_1`, `_2`… si la carpeta ya existe |
| `tree_stats` | Cantidad y suma de bytes de archivos regulares |
| `option_backup` | Parte interactiva y validaciones |
| `run_backup` | Copia, catálogo, verificación, `sync`, resumen |
| `print_backup_summary` | Resumen final y sugerencia de `umount` |

### Menú y entrada

| Función | Propósito |
|---|---|
| `cleanup` | Borra `TMP_FILES` (trap `EXIT`) |
| `on_interrupt` | Mensaje, aviso de copia INCOMPLETA y `exit` con el código recibido |
| `show_menu` | Imprime el menú con el `hostname` |
| `main` | Traps, dependencias, aviso de root y ciclo del menú |

## 4. Flujo de `main`

```text
main
 ├─ trap cleanup EXIT; trap 'on_interrupt 130' INT; trap 'on_interrupt 143' TERM
 ├─ check_dependencies || exit 1
 ├─ warn_if_not_root "no se está ejecutando como root; …"
 └─ ciclo:
     clear_screen → show_menu → read -r -p 'Seleccione una opción: ' choice
       ├─ EOF en stdin → salto de línea y break (evita ciclo infinito con entrada por tubería)
       ├─ 1..5 → option_users | option_filesystems | option_largest_files | option_memory | option_backup
       ├─ 0    → "Hasta luego." y break
       └─ otro → ERROR: opción no válida: '…'. Ingrese un número entre 0 y 5.
     pause
 exit 0
```

El valor de retorno de cada `option_*` se ignora a propósito: un error ya se
informó con `print_error` y el menú debe continuar.

La última parte del archivo es:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

Al hacer `source` del script (pruebas BATS) solo se definen las funciones.

## 5. Convenciones

- Variables siempre entre comillas y con llaves (`"${var}"`); variables de
  función declaradas `local`.
- Constantes en MAYÚSCULAS y `readonly`.
- Las funciones retornan 0/1; nunca hacen `exit` (salvo `on_interrupt`), para
  no cerrar el menú.
- Diagnóstico por stderr (`print_error`, `print_warning`), resultados por
  stdout.
- `read -r` siempre (no interpreta `\`). Rutas con `IFS= read -r`.
- `LC_ALL=C` al ejecutar comandos cuya salida se parsea (`lastlog*`, `last`,
  `date -d`, `df` de la opción 2, `find` de la opción 3, `sort` del catálogo).
- `--` antes de rutas de usuario (`cd -P --`, `du -sb --`, `cp --`, `mkdir --`,
  `rsync --`, `basename --`) para que una ruta que empiece por `-` no se tome
  como opción.
- Entradas numéricas con `10#${choice}` para que `08` no se interprete como
  octal inválido.
- Calidad: ShellCheck 0.11 sin advertencias; formato `shfmt -i 4 -ci`.

## 6. Manejo de errores

`set -uo pipefail`, deliberadamente **sin `-e`**:

- `-u`: usar una variable no definida es un error (detecta errores de tipeo).
- `-o pipefail`: el estado de una tubería es el del último comando que falló,
  no solo el del último (sin él, `find … | sort` "triunfa" aunque `find`
  falle). Consecuencia visible en `write_catalog`: `find | sort | tr` devuelve
  1 si `find` encontró un directorio ilegible, por eso se agrega `|| true`.
  Donde el valor importa (p. ej. `required="$(du -sb … | awk …)"`), el
  resultado se valida además con una expresión regular.
- Sin `-e`: con `errexit`, cualquier comando con estado ≠ 0 (un `find` que no
  pudo leer un directorio, un `grep` sin coincidencias, un `((n == 0))`)
  terminaría el programa completo. En un menú interactivo eso es inaceptable,
  y las reglas de `-e` (ignorado dentro de `if`, `&&`, funciones llamadas en
  condiciones) son difíciles de razonar. Cada función comprueba sus errores,
  imprime un mensaje en español y retorna 1.

Patrones:

- Validación antes de actuar (opción 5: nada se escribe hasta pasar todas las
  validaciones y la confirmación).
- Salidas de error de comandos externos redirigidas a `/dev/null` o a un
  archivo (opción 3) y sustituidas por mensajes propios.
- `|| true` donde un código ≠ 0 es esperable y no significa fallo
  (`write_catalog`: `find` devuelve 1 si encuentra un directorio ilegible).
- `read … || return 1`: EOF en la entrada aborta la opción limpiamente.

## 7. Manejo de señales

| Trap | Acción | Motivo |
|---|---|---|
| `EXIT` → `cleanup` | `rm -f` de `TMP_FILES` | Se ejecuta en cualquier salida (normal, `exit`, señal atrapada) |
| `INT` → `on_interrupt 130` | Mensaje "Interrupción recibida (señal). Saliendo...", aviso si hay copia en curso, `exit 130` | Ctrl+C. 130 = 128 + 2 (SIGINT), convención del shell |
| `TERM` → `on_interrupt 143` | Igual, `exit 143` | `kill PID`. 143 = 128 + 15 (SIGTERM) |

Mientras `run_backup` copia, `CURRENT_BACKUP_DIR` contiene la carpeta destino;
si llega una señal se imprime
`ADVERTENCIA: la copia de seguridad quedó INCOMPLETA en: …`. La carpeta **no
se borra** a propósito: el administrador decide si la elimina o la reutiliza.

Ctrl+C se envía a todo el grupo de procesos en primer plano: `rsync`/`find`
reciben SIGINT y terminan; bash ejecuta el trap cuando el comando hijo
termina. `SIGKILL` no se puede atrapar (no hay limpieza en ese caso).

## 8. Portabilidad

Probado (opciones 1 a 5 ejecutadas con éxito):

| Entorno | bash | Último login (opción 1) | Observaciones |
|---|---|---|---|
| WSL Ubuntu 26.04 | 5.3 | Por defecto no hay `lastlog`/`last` → "No disponible" + sugerencia de instalar. Con `lastlog2` instalado: `/usr/bin/lastlog2`. Solo con `wtmpdb`: `last --time-format iso` | `du`, `sort`, `head`, `numfmt` son uutils (Rust); `df` y `cp` son GNU. util-linux 2.41. Sin USB física |
| Debian 13 (Docker) | 5.2 | Paquete `lastlog2` | — |
| Fedora 45 (Docker) | 5.3 | `/usr/sbin/lastlog2` (encontrado gracias a `SBIN_DIRS`) | La imagen base no trae `lsblk`: el script informa la dependencia faltante en español (instalar `util-linux`) |
| Rocky Linux 9.3 (Docker) | 5.1 | `lastlog` de shadow-utils: "No disponible" si no existe `/var/log/lastlog`; si existe, fecha/hora o "Nunca ha iniciado sesión" | — |

Requisitos de portabilidad que no se cumplen fuera de Linux GNU: `find
-printf`, `df --output`, `findmnt`, `lsblk`, `/proc/meminfo` (no hay versión
para BusyBox, macOS ni BSD).

Finales de línea: `.gitattributes` fuerza LF en `*.sh`, `*.bash`, `*.bats` y
`*.md`. Un script con CRLF falla en bash con `$'\r': command not found`
porque `\r` pasa a formar parte de cada comando.
