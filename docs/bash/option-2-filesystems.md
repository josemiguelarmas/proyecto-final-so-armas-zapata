# Opción 2 — Sistemas de archivos y discos

## Requisito

> Desplegar los filesystems o discos conectados a la máquina. Incluir para cada
> disco su tamaño y la cantidad de espacio libre (en bytes).

Se muestran ambas vistas: los **sistemas de archivos montados** (tamaño y
libre, que solo existen para algo montado) y los **discos físicos** (tamaño
del dispositivo, montado o no).

## Comandos usados, y por qué

| Comando | Uso | Por qué |
|---|---|---|
| `df -B1 --output=source,fstype,size,avail,target` | Tabla principal | `-B1` = bloques de 1 byte → valores exactos en bytes, como pide el enunciado. `--output` fija las columnas y su orden, así el parseo no depende del formato por defecto. `df` lee la tabla de montajes del kernel y llama a `statvfs()` en cada uno. |
| `df … -x TIPO` (repetido) | Oculta pseudo-sistemas de archivos | `tmpfs`, `devtmpfs`, `squashfs`, `overlay`, etc. no son discos; saturan la lista (en Ubuntu, cada snap es un `squashfs`). |
| `lsblk -b -d -e 1,7 -o NAME,TYPE,SIZE,RM,TRAN,MODEL` | Discos físicos | `-b` tamaño en bytes; `-d` solo discos completos, sin particiones; `-e 1,7` excluye los números mayores 1 (`ram`) y 7 (`loop`, imágenes de snap); `RM` removible, `TRAN` transporte (`sata`, `nvme`, `usb`). |

Alternativas descartadas:

- **`df -h`**: unidades redondeadas (`G`, `M`), no bytes.
- **Solo `lsblk`**: da el tamaño del dispositivo pero no el espacio libre
  (la columna `FSAVAIL` solo existe para lo montado y depende de la versión).
- **Leer `/proc/mounts` y calcular con `stat -f`**: reimplementa lo que `df`
  ya hace.
- **`fdisk -l`**: requiere root y no informa espacio libre del sistema de
  archivos.

`LC_ALL=C df`: el encabezado y formato no dependen del idioma; `tail -n +2`
quita el encabezado.

## Algoritmo (`option_filesystems`)

1. Pregunta `¿Incluir pseudo-sistemas de archivos (tmpfs, overlay, ...)? [s/N]:`.
   Si la respuesta no es `s`/`S`, agrega `-x TIPO` por cada elemento de
   `PSEUDO_FS_TYPES` (`tmpfs devtmpfs squashfs overlay efivarfs ramfs rootfs
   proc sysfs devpts cgroup cgroup2 autofs`). La opción por defecto (Enter)
   los oculta.
2. Lee cada línea con `read -r source fstype size avail target`. `read`
   asigna **todo el resto de la línea a la última variable**, por eso un punto
   de montaje con espacios queda completo en `target`.
3. Si no hubo filas → `ERROR: df no devolvió ningún sistema de archivos.`
4. Calcula el ancho de las columnas de texto con `max_length` (longitud del
   valor más largo, incluido el encabezado) para que la tabla quede alineada;
   las columnas numéricas tienen ancho fijo de 18.
5. Imprime la tabla y luego `lsblk`. Si `lsblk` falla:
   `ADVERTENCIA: no se pudo obtener la información de lsblk.`

## Columnas

| Columna | Origen | Significado |
|---|---|---|
| DISPOSITIVO | `source` | Dispositivo o fuente del montaje (`/dev/sdd`, `C:\` en WSL) |
| TIPO | `fstype` | `ext4`, `vfat`, `9p`, … |
| TOTAL (BYTES) | `size` | Tamaño total del sistema de archivos |
| DISPONIBLE (BYTES) | `avail` | Espacio que puede usar un usuario sin privilegios |
| MONTAJE | `target` | Punto de montaje |

Por qué `avail` y no `size - used`: ext4 reserva por defecto ~5 % de los
bloques para root. `avail` ya descuenta esa reserva y es lo realmente
utilizable; por eso `size - used` suele ser mayor que `avail`.

## Permisos

`df` y `lsblk` funcionan sin root: `statvfs()` y `/sys/block` son accesibles
a cualquier usuario. Puede faltar algún montaje inaccesible para el usuario
(se descartan los errores de `df` con `2>/dev/null`).

## Casos borde

| Caso | Comportamiento |
|---|---|
| Punto de montaje con espacios | Correcto (último campo de `read`) |
| Dispositivo (SOURCE) con espacios | Columnas desplazadas — limitación conocida |
| Sistema de archivos solo lectura (ISO) | Disponible = 0 (ver `/dev/loop0 iso9660` en el ejemplo) |
| Respuesta `s` | Se listan también `tmpfs`, `overlay`, etc. |
| `lsblk` ausente | El script no arranca: `lsblk` está en `REQUIRED_CMDS` (caso real en la imagen base de Fedora) |

## Diferencias entre distribuciones

- En WSL aparecen montajes `9p` (`drivers`, `C:\` en `/mnt/c`): son el disco
  de Windows compartido, no se ocultan porque sí son almacenamiento real.
- En contenedores Docker la raíz es `overlay` → se oculta por defecto
  (responder `s` para verla).
- `lsblk` en WSL muestra discos virtuales (`Virtual Disk`) sin `TRAN`.

## Ejemplo real

WSL Ubuntu 26.04, usuario normal. Entrada: `2`, Enter (por defecto se excluyen
los pseudo-sistemas de archivos). `/mnt/usb_demo` es una imagen vfat montada
con loop para simular una USB.

```text
=== Sistemas de archivos y discos ===

DISPOSITIVO  TIPO          TOTAL (BYTES)  DISPONIBLE (BYTES)  MONTAJE
-----------------------------------------------------------------------------------------------
/dev/loop0   iso9660           818345984                   0  /mnt/wsl/docker-desktop/cli-tools
drivers      9p             476155211776         47320285184  /usr/lib/wsl/drivers
/dev/sdd     ext4          1081101176832       1024264241152  /
C:\          9p             476155211776         47320285184  /mnt/c
/dev/loop2   vfat              209489920           209489920  /mnt/usb_demo

Discos físicos (lsblk -b):
NAME TYPE          SIZE RM TRAN MODEL
sda  disk     374251520  0      Virtual Disk    
sdb  disk     167149568  0      Virtual Disk    
sdc  disk    4294971392  0      Virtual Disk    
sdd  disk 1099511627776  0      Virtual Disk    
sde  disk 1099511627776  0      Virtual Disk    
sdf  disk     148317184  0      Virtual Disk    
```

Observación: `/dev/sdd` mide 1099511627776 bytes como disco (`lsblk`) pero su
ext4 reporta 1081101176832 bytes totales (`df`): la diferencia son los
metadatos del sistema de archivos (tablas de inodos, journal).

## Preguntas probables de la sustentación

**¿Por qué `df -B1` y no `df -h`?**
El enunciado pide bytes. `-h` redondea a unidades legibles y pierde
precisión; `-B1` da el valor exacto.

**¿Por qué el tamaño de `lsblk` y el de `df` no coinciden?**
`lsblk` mide el dispositivo de bloques; `df` el sistema de archivos dentro,
que descuenta metadatos (inodos, journal, superbloques).

**¿Por qué "disponible" es menor que "total − usado"?**
ext4 reserva bloques para root (por defecto 5 %). `avail` es lo que puede
usar un usuario normal.

**¿Por qué ocultan tmpfs, overlay, squashfs?**
No son discos: viven en RAM (`tmpfs`, `devtmpfs`), son imágenes de solo
lectura (`squashfs` de snap) o capas de contenedor (`overlay`). Se pueden
incluir respondiendo `s`.

**¿Cómo manejan un punto de montaje con espacios?**
`target` es la última variable de `read`, que recibe todo el resto de la línea.
No funciona si el espacio está en el **dispositivo** (columna anterior).

**¿Qué hace `-e 1,7` en `lsblk`?**
Excluye dispositivos por número mayor: 1 = `ram`, 7 = `loop`. Así se ven solo
los discos reales.
