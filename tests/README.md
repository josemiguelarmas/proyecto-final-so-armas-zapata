# Pruebas de `bash/sysadmin-tool.sh`

Suite automatizada con [BATS](https://github.com/bats-core/bats-core) (Bash
Automated Testing System) para la herramienta de administración en BASH.

## Requisitos

- Linux (probado en WSL Ubuntu 26.04, bash 5.3, bats 1.13, util-linux 2.41).
- `bats`, `shellcheck`, `rsync`, `findmnt`/`lsblk` (util-linux), `unshare`.
- Para las pruebas de root: `losetup`, `mkfs.ext4` (e2fsprogs), `mkfs.vfat`
  (dosfstools) y soporte de dispositivos loop.
- Recomendado: `lastlog2` + `libpam-lastlog2` y `wtmpdb` (comando `last`).

```bash
sudo apt install bats shellcheck rsync dosfstools e2fsprogs lastlog2 libpam-lastlog2 wtmpdb
```

## Cómo ejecutar

Desde la raíz del repositorio:

```bash
# Como usuario normal (las pruebas que necesitan root se marcan "skip")
tests/run-tests.sh

# Como root: ejecuta además las pruebas con montajes, loops, tmpfs, vfat...
sudo tests/run-tests.sh

# Solo algunos archivos u opciones extra de bats
tests/run-tests.sh test_menu.bats test_option3_largest.bats
tests/run-tests.sh --tap
tests/run-tests.sh -f 'opción 5'
```

También puede llamarse a bats directamente: `bats tests/`.

Se recomienda ejecutar la suite **dos veces** (usuario normal y root): hay
pruebas exclusivas de cada caso (por ejemplo, las advertencias de permisos
solo se pueden comprobar sin privilegios, porque root ignora los permisos).

Las pruebas crean sus archivos en `BATS_TEST_TMPDIR` (bajo `/tmp`) y los
montajes/loops se liberan en `teardown`. Las imágenes y montajes temporales
usan el prefijo `qa_`.

## Archivos

| Archivo | Qué cubre |
|---|---|
| `test_helper.bash` | Funciones compartidas: `run_tool` (ejecuta el menú con líneas de entrada), `run_fn` (carga el script con `source` y prueba funciones sueltas), `make_temp_dir`, `make_stub` (binarios falsos en `PATH`), `make_min_path` (PATH mínimo sin `lastlog2`/`last`/`rsync`), `require_root`, `mount_tmpfs`, `make_loop_ext4`, `cleanup_mounts`. |
| `test_menu.bats` | Menú: opciones inválidas (letras, 9, -1, vacío, 00, 10) con error en español y continuación del ciclo; `0` sale con código 0; EOF termina el ciclo; errores por stderr; sin prompts ni escapes sin TTY; advertencia de no-root; dependencias faltantes (código 1); SIGTERM (código 143); limpieza de temporales (sin `/tmp/tmp.*` sobrantes). |
| `test_option1_users.bats` | `is_human_uid` (root, UID ≥ 1000, `nobody` = sistema); análisis de `lastlog`/`lastlog2` (Port/From vacíos, `**Never logged in**`, salida vacía, fecha ilegible); análisis de `last` ISO (sesión cerrada, activa, `wtmpdb begins` sin registros); cadena de detección `lastlog2 → lastlog → last`; tabla completa con `getent` falso; "Nunca ha iniciado sesión"; "No disponible" sin herramientas; columnas FECHA y HORA; integración con el sistema real. |
| `test_option2_filesystems.bats` | `max_length`; `df -B1`; exclusión por defecto de tmpfs/devtmpfs/squashfs/overlay e inclusión con `s`/`S`; tamaños en bytes iguales a `df`; número de filas; alineación de columnas; punto de montaje con espacios (loop ext4, root); tmpfs nuevo solo con `s` (root). |
| `test_option3_largest.bats` | `resolve_search_path` (relativo/enlace → absoluto, inexistente, archivo, dispositivo montado/no montado, sin permiso); `human_size` con numfmt y con awk; máximo 10 resultados ordenados; bytes y tamaño legible; directorio vacío; solo archivos regulares; nombres con espacios, tabuladores, saltos de línea, caracteres especiales y guion inicial; advertencia de permisos (no root); `-xdev` con tmpfs anidado (root); dispositivo loop montado y sin montar (root). |
| `test_option4_memory.bats` | `percentage`; MemTotal y SwapTotal = valor de `/proc/meminfo` × 1024; coherencia libre ≤ disponible ≤ total; porcentajes con dos decimales; con un `/proc/meminfo` falso (`unshare -m` / `unshare -rm` + `mount --bind`): valores exactos, SwapTotal = 0, sin MemAvailable (estimación y advertencia), sin líneas de swap, valores de TiB, archivo inválido. |
| `test_option5_backup.bats` | `unique_backup_dir`, `is_fat_filesystem`, `tree_stats`, `print_field`; copia exitosa a otro FS (`/dev/shm`) y al mismo FS (advertencia); carpeta `backup_<nombre>_AAAAmmdd_HHMMSS` con `<nombre>/` y `catalogo.txt` (rutas relativas + fecha); `diff -r`; fechas conservadas; nombres especiales; origen vacío; dos copias en el mismo segundo (`_1`); respaldo con `cp -a` sin rsync; errores (origen inexistente/archivo/ilegible, destino dentro del origen, igual al origen, vía enlace, prefijo hermano `/x/datos2` permitido, destino inexistente/archivo/sin escritura, ruta vacía, opción inválida, `08`, cancelar, no confirmar); detección USB con `lsblk` falso; archivo ilegible ⇒ FALLIDA; SIGTERM durante la copia ⇒ INCOMPLETA; root: espacio insuficiente, solo lectura, vfat, USB simulada con loop. |
| `test_option5_backup.bats` (entrada) | Secuencia de stdin: `5`, origen, destino (`1..N`, `m` o `c`), [ruta si `m`], [`s` extra si el destino está en el sistema de archivos raíz `/`], confirmación `s`/`n`, Enter, `0`. `backup_lines` construye esta secuencia automáticamente. También: `~`/`~/` se expanden a `$HOME`, espacios al inicio/fin se respetan, catálogo con salto de línea mostrado como `?`. |
| `test_static.bats` | `shellcheck` sin hallazgos, `bash -n`, shebang `#!/usr/bin/env bash`, bit de ejecución (sistema de archivos e índice de git), sin CRLF (script y pruebas), `source` no ejecuta el menú. |
| `run-tests.sh` | Lanzador: ejecuta bats sobre `tests/` (o los archivos indicados) y pasa las demás opciones a bats. |

## Pruebas que requieren root

Se marcan `skip` automáticamente si no se ejecutan como root:

- `test_menu.bats`: "como root no muestra la advertencia de privilegios".
- `test_option2_filesystems.bats`: punto de montaje con espacios (loop ext4);
  tmpfs nuevo visible solo con `s`.
- `test_option3_largest.bats`: sin advertencias como root; `-xdev` con tmpfs
  anidado; punto de montaje exacto; dispositivo loop montado; loop sin montar.
- `test_option5_backup.bats`: espacio insuficiente (tmpfs de 4 MiB); destino
  de solo lectura; destino vfat; USB simulada (loop + `lsblk` falso).

Y a la inversa, se omiten como root (root ignora permisos): advertencia de no
root, directorio ilegible en la opción 3, origen ilegible, destino sin
escritura y archivo ilegible ⇒ FALLIDA en la opción 5.

Las pruebas de `/proc/meminfo` falso usan `unshare -m` como root o
`unshare -rm` (espacio de nombres de usuario) como usuario normal; si el
kernel no lo permite se omiten.

## Pruebas manuales

Procedimientos reproducibles para lo que no se puede automatizar de forma
fiable.

### M1. Interrupción con Ctrl+C en el menú

1. `bash/sysadmin-tool.sh` en una terminal interactiva.
2. Pulsar Ctrl+C en el prompt "Seleccione una opción:".
3. Esperado: "Interrupción recibida (señal). Saliendo...", `echo $?` = 130
   (con SIGTERM, `kill <pid>`, el código es 143).
   La prueba automática usa SIGTERM porque, en un proceso en segundo plano no
   interactivo, bash ignora SIGINT.

### M2. Ctrl+C durante una copia de seguridad grande

1. Crear un origen grande: `mkdir /tmp/qa_big && head -c 2G /dev/urandom > /tmp/qa_big/f`.
2. Opción 5 → origen `/tmp/qa_big` → `m` → destino `/dev/shm` u otro disco → `s`.
3. Pulsar Ctrl+C mientras dice "Copiando archivos...".
4. Esperado: "ADVERTENCIA: la copia de seguridad quedó INCOMPLETA en: …",
   código 130. Borrar la carpeta parcial a mano.

### M3. Memoria USB real

1. En Linux nativo (o WSL con `usbipd attach --wsl`), conectar una USB
   formateada en FAT32 o exFAT y montarla (p. ej. en `/media/$USER/USB`).
2. Opción 2: la USB aparece en la tabla y en "Discos físicos (lsblk -b)"
   con `RM=1` y `TRAN=usb`.
3. Opción 5: debe aparecer como `1) /dev/sdX1 (tamaño) montado en …`;
   elegir `1`, confirmar `s`.
4. Esperado: advertencia de destino FAT, método `rsync -rt --modify-window=2`,
   verificación EXITOSA, y el mensaje con el `umount` sugerido. Ejecutar el
   `umount` y comprobar que la USB se desmonta sin errores.
5. Repetir con una USB llena (o casi llena) y un origen mayor al espacio
   libre: esperado "espacio insuficiente en el destino".

### M4. Clear de pantalla en terminal

1. Ejecutar la herramienta en una terminal real.
2. Esperado: la pantalla se limpia antes de cada menú y se muestran los
   prompts ("Seleccione una opción:", "Presione Enter…"). Con
   `bash/sysadmin-tool.sh | cat` no deben aparecer secuencias de escape.

### M5. Otras distribuciones

1. En RHEL/Rocky 9 (solo `lastlog` de shadow-utils) y en Fedora reciente
   (`lastlog2` en `/usr/sbin`, fuera del PATH de un usuario normal),
   ejecutar la opción 1 como usuario normal.
2. Esperado: "Fuente del último inicio de sesión: /usr/sbin/lastlog2" (o
   `lastlog`), fechas correctas y "Nunca ha iniciado sesión" para cuentas
   nuevas.

### M6. Inicio de sesión real

1. `sudo useradd -m qa_user && sudo passwd qa_user`.
2. Opción 1 / 1: `qa_user` → "Nunca ha iniciado sesión".
3. `su - qa_user` (o SSH), salir, repetir la opción 1: ahora muestra la fecha
   y hora del inicio de sesión. Limpiar con `sudo userdel -r qa_user`.
