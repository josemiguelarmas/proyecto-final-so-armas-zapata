# Opción 3 — Los diez archivos más grandes

## Requisito

> Desplegar el nombre y el tamaño de los diez archivos más grandes almacenados
> en un disco o filesystem que el usuario deberá especificar. Los archivos
> deben aparecer con su trayectoria completa.

## Comandos usados, y por qué

Tubería central:

```bash
LC_ALL=C find "${search_path}" -xdev -type f -printf '%s\t%p\0' 2>"${err_file}" |
    sort -z -rn | head -z -n 10
```

| Elemento | Por qué |
|---|---|
| `find -type f` | Solo archivos regulares (no directorios, enlaces, dispositivos) |
| `-xdev` | No entra en otros sistemas de archivos montados debajo de la ruta. El requisito habla de **un** disco/filesystem: buscar en `/` no debe recorrer `/mnt/c`, `/proc` ni una USB montada |
| `-printf '%s\t%p\0'` | `%s` tamaño en bytes (tamaño aparente), `%p` ruta completa; el tamaño sale del mismo `stat()` que hace `find`, sin procesos extra |
| `\0` (NUL) como fin de registro | El NUL es el único byte que no puede estar en una ruta de Linux. Con `\n` un nombre con salto de línea se partiría en dos registros |
| `sort -z -rn` | `-z` registros NUL, `-n` numérico (el tamaño al inicio), `-r` descendente |
| `head -z -n 10` | Diez primeros registros NUL |
| `findmnt -n -f -o TARGET --source DEV` | Traduce un dispositivo (`/dev/sdb1`) a su punto de montaje |
| `findmnt -n -o TARGET -T RUTA` | Sistema de archivos al que pertenece una ruta (para la nota informativa) |
| `human_size` (`numfmt --to=iec-i`) | Columna LEGIBLE; respaldo en `awk` si no hay `numfmt` |

Alternativas descartadas:

- **`du -a | sort -n | tail`**: `du` mide bloques ocupados en disco (no el
  tamaño del archivo) e incluye directorios en la lista.
- **`ls -lR` y parsear**: la salida de `ls` no es parseable de forma segura
  (nombres con espacios/saltos de línea, formato de fecha variable).
- **`find -exec stat -c '%s %n' {} \;`**: un proceso por archivo; muchísimo
  más lento. `-printf` lo hace dentro de `find`.
- **Delimitar con `\n`**: se rompe con nombres que contienen saltos de línea.

## Algoritmo

1. `option_largest_files` pide la ruta con `read_path` (`IFS= read -r`,
   conserva espacios, expande `~`). Vacía → `ERROR: no se ingresó ninguna ruta.`
2. `resolve_search_path` normaliza la entrada:
   - **Dispositivo de bloques** (`-b`): `findmnt --source` → primer punto de
     montaje. No montado → `ERROR: el dispositivo '…' no está montado; móntelo antes de buscar.`
   - **Directorio** (`-d`): `cd -P` + `pwd -P` en una subshell → ruta
     absoluta física (resuelve rutas relativas y enlaces simbólicos, así
     `find` imprime rutas completas). Sin permiso de entrar →
     `ERROR: no hay permiso para acceder a '…'.`
   - **Otro tipo de archivo**: `ERROR: '…' no es un directorio ni un dispositivo de bloques.`
   - **No existe**: `ERROR: '…' no existe.`
3. Si la ruta no es raíz de un montaje, informa a qué sistema de archivos
   pertenece y que la búsqueda no saldrá de él.
4. Advierte si no es root y que la búsqueda puede tardar.
5. Crea un temporal con `mktemp` **en el shell actual** (no dentro de `$(…)`
   de otra función, porque esa subshell no podría registrar el archivo) y lo
   agrega a `TMP_FILES` para que `cleanup` lo borre al salir.
6. Ejecuta la tubería; el stderr de `find` va al temporal. Lee cada registro
   completo con `IFS= read -r -d ''` (`-d ''` = delimitador NUL) y lo separa
   a mano en el **primer** tabulador: `size="${record%%$'\t'*}"`,
   `file="${record#*$'\t'}"`. No se usa `IFS=$'\t' read size file` porque
   `read` eliminaría un tabulador al final del nombre del archivo.
7. Imprime `#`, BYTES, LEGIBLE, RUTA. Un salto de línea dentro de un nombre se
   muestra como `\n` (`${file//$'\n'/\\n}`) para no romper la tabla.
8. Sin resultados → `No se encontraron archivos regulares en …`.
9. Cuenta las líneas del temporal (`wc -l`); si hay errores →
   `ADVERTENCIA: find no pudo leer N ruta(s) (permisos u otros errores); los resultados pueden estar incompletos.`
   `sort` no emite nada hasta que `find` termina, así que el archivo de
   errores está completo cuando se cuenta.

## Permisos

Sin root, `find` no puede entrar en directorios como `/root`, `/var/lib/…`,
`/etc/ssl/private`. No se ocultan esos errores sin más: se cuentan y se avisa
que el resultado puede estar incompleto. Para un resultado completo:
`sudo ./bash/sysadmin-tool.sh`.

## Casos borde (verificados)

| Caso | Resultado |
|---|---|
| Nombres con espacios, tabuladores, `$`, `&`, `*` | Correctos (NUL + comillas) |
| Nombre con salto de línea | Un solo registro, mostrado con `\n` |
| `tmpfs` montado dentro de la ruta | Excluido por `-xdev` |
| Dispositivo montado (`/dev/sdd`) | Se busca en su punto de montaje (`/`) |
| Dispositivo sin montar | Error en español |
| Ruta inexistente, archivo regular, entrada vacía | Error en español |
| Usuario normal | Advertencia "find no pudo leer N ruta(s)…" |
| Ruta relativa o enlace simbólico | Se convierte en ruta absoluta física |
| Menos de 10 archivos | Se muestran los que haya |

## Diferencias entre distribuciones

Requiere GNU `find` (`-printf`); `sort -z` y `head -z` están en GNU coreutils
y en uutils (Ubuntu 26.04 usa uutils para `sort`/`head`/`numfmt`; se verificó
que funciona). No hay versión para BusyBox ni BSD.

## Ejemplos reales

WSL Ubuntu 26.04, usuario normal.

Entrada `3`, `/usr` (directorio que no es punto de montaje):

```text
=== Los diez archivos más grandes ===


Buscando en: /usr
Nota: no es un punto de montaje; pertenece al sistema de archivos montado en /.
Se busca solo dentro de esta ruta, sin salir de ese sistema de archivos.
ADVERTENCIA: sin privilegios de root algunos directorios pueden no ser accesibles.
Esto puede tardar en sistemas de archivos grandes...

  #             BYTES     LEGIBLE  RUTA
  1         138567144    132.2MiB  /usr/lib/x86_64-linux-gnu/libLLVM.so.21.1
  2          45621592     43.6MiB  /usr/lib/x86_64-linux-gnu/libgallium-26.0.8-1ubuntu0.3.so
  3          33654424     32.1MiB  /usr/lib/snapd/snapd
  4          24967304     23.9MiB  /usr/bin/snap
  5          23538064     22.5MiB  /usr/lib/x86_64-linux-gnu/libvulkan_intel.so
  6          23388408     22.4MiB  /usr/bin/shellcheck
  7          19302384     18.5MiB  /usr/lib/x86_64-linux-gnu/libvulkan_intel_hasvk.so
  8          18166848     17.4MiB  /usr/lib/x86_64-linux-gnu/libvulkan_radeon.so
  9          17025720     16.3MiB  /usr/lib/x86_64-linux-gnu/libvulkan_nouveau.so
 10          15125944     14.5MiB  /usr/lib/snapd/snap-bootstrap
```

Entrada `3`, `/dev/sdd` (dispositivo; se traduce a `/`). En este caso no hubo
advertencia de lectura en `/usr`, pero sí en `/`:

```text
=== Los diez archivos más grandes ===


Buscando en: /
ADVERTENCIA: sin privilegios de root algunos directorios pueden no ser accesibles.
Esto puede tardar en sistemas de archivos grandes...

  #             BYTES     LEGIBLE  RUTA
  1         209715200    200.0MiB  /var/tmp/disk.img
  2         209715200    200.0MiB  /var/tmp/demo.img
  3         138567144    132.2MiB  /usr/lib/x86_64-linux-gnu/libLLVM.so.21.1
  4         104857600    100.0MiB  /var/tmp/b5fat.img
  5         104857600    100.0MiB  /var/tmp/b5ext.img
  6          76792699     73.3MiB  /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_resolute_universe_binary-amd64_Packages
  7          55508197     53.0MiB  /var/cache/apt/pkgcache.bin
  8          55463792     52.9MiB  /var/cache/apt/srcpkgcache.bin
  9          45621592     43.6MiB  /usr/lib/x86_64-linux-gnu/libgallium-26.0.8-1ubuntu0.3.so
 10          33654424     32.1MiB  /usr/lib/snapd/snapd

ADVERTENCIA: find no pudo leer 21 ruta(s) (permisos u otros errores); los resultados pueden estar incompletos.
```

Gracias a `-xdev`, la búsqueda en `/` no entró en `/mnt/c` (disco de Windows)
ni en `/mnt/usb_demo`.

## Limitaciones

- En un sistema de archivos grande el recorrido completo es lento (se lee el
  inodo de cada archivo).
- Se reporta el tamaño aparente (`%s`), no los bloques ocupados: un archivo
  disperso (*sparse*) puede aparecer grande sin ocupar ese espacio.
- Si un dispositivo está montado en varios lugares se usa el primero
  (`findmnt -f`).

## Preguntas probables de la sustentación

**¿Por qué `-xdev`?**
El usuario elige un disco/filesystem. Sin `-xdev`, buscar en `/` recorrería
también otros discos montados debajo (`/mnt/c`, USB, `/proc`) y mezclaría
resultados de varios dispositivos.

**¿Por qué separar registros con NUL?**
Es el único byte prohibido en rutas Linux. Con saltos de línea, un archivo
llamado `a\nb` se convertiría en dos registros y desordenaría la lista.

**¿Por qué `find -printf` y no `du` o `ls`?**
`du` reporta bloques ocupados e incluye directorios; `ls` no es parseable con
seguridad. `-printf '%s'` da el tamaño exacto en bytes sin lanzar un proceso
por archivo.

**¿Cómo convierten un dispositivo en ruta?**
`findmnt -n -f -o TARGET --source /dev/sdX` consulta la tabla de montajes del
kernel. Si no está montado no hay sistema de archivos que recorrer, y se
informa el error.

**¿Qué pasa si se ejecuta sin root?**
`find` no puede leer algunos directorios; sus errores se guardan en un
temporal, se cuentan y se muestra una advertencia con el número de rutas no
leídas.

**¿Cómo se garantiza que se borre el archivo temporal?**
Se registra en `TMP_FILES` y `trap cleanup EXIT` lo borra en cualquier salida,
incluida una interrupción con Ctrl+C.
