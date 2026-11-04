# Opción 5 — Copia de seguridad a memoria USB

## Requisito

> Hacer copia de seguridad (backup) de un directorio especificado a una memoria
> USB. Además de los archivos, se debe almacenar un catálogo que contenga los
> nombres de los archivos y su fecha de última modificación.

## Resultado en el destino

```text
<destino>/backup_<nombre>_AAAAmmdd_HHMMSS/
├── <nombre>/        # copia del contenido del directorio de origen
└── catalogo.txt     # ruta relativa <TAB> fecha y hora de modificación
```

- El nombre lleva fecha y hora para que cada copia sea independiente y nunca
  sobrescriba una anterior. Si dos copias empiezan en el mismo segundo,
  `unique_backup_dir` agrega `_1`, `_2`…
- `catalogo.txt` va **fuera** de la carpeta de datos: no se mezcla con los
  archivos respaldados ni altera el conteo de la verificación.

## Comandos usados, y por qué

| Comando | Uso | Por qué / alternativas |
|---|---|---|
| `lsblk -dnpr -o NAME,TYPE,RM,HOTPLUG,TRAN` | Detectar discos USB/removibles | `TRAN=usb` identifica el bus; `RM=1` o `HOTPLUG=1` cubre discos que no reportan USB (muchos SSD USB tienen `RM=0`). `-d` discos completos, `-n` sin encabezado, `-p` rutas completas, `-r` formato crudo; `TRAN` va al final porque está vacío en discos no USB y no desplaza los demás campos. |
| `lsblk -npr -o NAME,SIZE DISCO` | El disco y sus particiones | Una USB puede estar montada como disco entero o por partición. |
| `findmnt -n -o TARGET --source PART` | Puntos de montaje de cada partición | Lee la tabla de montajes del kernel; más fiable que parsear `mount` o `/proc/mounts`. |
| `findmnt -n -o TARGET -T RUTA` / `-o FSTYPE` | A qué montaje y tipo de FS pertenece una ruta | Validaciones y elección de opciones de copia. |
| `du -sb ORIGEN` | Espacio requerido | `-s` total, `-b` tamaño aparente en bytes. |
| `df -B1 --output=avail DESTINO` | Espacio disponible | Bytes que puede usar un usuario normal. |
| `rsync` | Copia | Copia incremental robusta, reporta errores por archivo con códigos de salida precisos (p. ej. 23 = transferencia parcial). Respaldo: `cp`. |
| `find -printf '%P\t%TY-%Tm-%Td %TH:%TM:%TS\0'` | Catálogo | `%P` ruta relativa al origen; `%T…` fecha de modificación. Sin procesos extra por archivo (vs. `stat` en un ciclo). |
| `find -type f -printf` + `awk` | Verificación (`tree_stats`) | Cantidad y suma de bytes de archivos regulares. |
| `sync` | Vaciar cachés al dispositivo | Linux escribe en la caché de páginas y vacía después; retirar la USB sin `sync` puede perder datos. |

### Opciones de copia según el sistema de archivos destino (`copy_tree`)

| Destino | Con `rsync` | Sin `rsync` |
|---|---|---|
| ext4, xfs, … | `rsync -a` | `cp -a` |
| FAT (`vfat`, `msdos`, `fat`, `exfat`) | `rsync -rt --modify-window=2` | `cp -r --preserve=timestamps` |

- `-a` (archivo) = `-rlptgoD`: recursivo, enlaces simbólicos, permisos,
  fechas, grupo, propietario, dispositivos. Conserva todo lo posible. Sin root
  no se puede asignar otro propietario: los archivos quedan a nombre del
  usuario que ejecuta.
- En FAT no existen propietarios, permisos Unix ni enlaces simbólicos;
  pedirlos con `-a` produce errores en cada archivo y una copia "fallida" que
  en realidad está bien. Por eso solo `-r` (recursivo) y `-t` (fechas). Los
  enlaces simbólicos se omiten (rsync informa `skipping non-regular file`).
- `--modify-window=2`: FAT guarda fechas con resolución de 2 s. Esta opción
  hace que rsync considere iguales fechas que difieren ≤ 2 s al comparar
  origen y destino. Como cada copia va a una carpeta nueva, en la primera copia
  no cambia el resultado; evita recopias innecesarias si se resincroniza la
  misma carpeta.
- La barra final en `"${src}/"` hace que rsync copie el **contenido** del
  origen dentro de `<nombre>/` (sin ella crearía `<nombre>/<nombre>`). En `cp`
  se usa `"${src}/."` con el mismo fin.

### Verificación: por qué conteo + bytes de archivos regulares y no `du -sb`

`tree_stats` cuenta archivos regulares (`find -type f`) y suma sus tamaños.
No se compara `du -sb` del origen con el de la copia porque:

- el tamaño de los **directorios** difiere entre sistemas de archivos (4096
  bytes en ext4, otro valor en vfat);
- las implementaciones de `du` difieren (GNU vs. uutils en Ubuntu 26.04);
- los enlaces simbólicos no existen en la copia FAT.

Comparar solo archivos regulares hace que una copia correcta a vfat dé
EXITOSA. No es una comparación de contenido; la verificación fuerte opcional
es `rsync -rcn --itemize-changes ORIGEN/ COPIA/` (checksums, sin copiar nada).

## Algoritmo

`option_backup` (interactiva, **todo se valida antes de escribir**):

1. Advertencia si no es root.
2. `read_path 'Directorio a respaldar: '` → `validate_backup_source`:
   - no existe → `ERROR: el directorio de origen '…' no existe.`
   - no es directorio → `ERROR: '…' no es un directorio.`
   - sin lectura (`-r`) o sin permiso de atravesar (`-x`) →
     `ERROR: no tiene permiso de lectura sobre '…'.`
   Luego `absolute_dir` (`cd -P` + `pwd -P`) da la ruta absoluta física.
3. `select_destination`: muestra `lsblk -e 1,7 -o NAME,RM,TRAN,SIZE,MOUNTPOINT`,
   llama a `find_usb_mount_points` y ofrece `1..N` (USB detectadas,
   "`/dev/sdX1 (TAMAÑO) montado en RUTA`"), `m` (ruta manual) o `c`
   (cancelar). Opción inválida → `ERROR: opción de destino no válida: '…'.`
   La elección numérica usa `10#${choice}` para que `08` no sea octal inválido.
4. El destino debe existir y ser directorio
   (`ERROR: el destino '…' no existe o no es un directorio.`); se obtiene su
   ruta absoluta física.
5. `validate_backup_destination`:
   - pertenece a un montaje (`findmnt -T`);
   - escribible (`-w`, que usa `access(W_OK)` y también falla con `EROFS` en
     un montaje de solo lectura) →
     `ERROR: no tiene permiso de escritura en '…' (o está montado como solo lectura).`;
   - **no está dentro del origen**: `[[ "${dest}/" == "${src%/}/"* ]]`. Si lo
     estuviera, la copia se copiaría a sí misma recursivamente. La `/` final
     evita el falso positivo de `/x/a2` frente a `/x/a`; también rechaza
     destino = origen. → `ERROR: el destino no puede estar dentro del directorio de origen.`
   - mismo sistema de archivos que el origen → advertencia (no protege ante
     una falla de ese disco).
6. Si el destino está en `/` (raíz), advertencia y confirmación extra: casi
   siempre significa que la USB **no** está montada ahí (p. ej. una carpeta
   `/media/usb` vacía) y se llenaría el disco del sistema.
7. `du -sb` del origen → `check_free_space` contra `df --output=avail`. Si
   `requerido >= disponible` → `ERROR: espacio insuficiente en el destino.`
8. Calcula `backup_<nombre>_<fecha>` con `unique_backup_dir`, muestra origen,
   destino y tipo de FS; si es FAT,
   `ADVERTENCIA: destino FAT: no se conservan propietarios, permisos ni enlaces simbólicos.`
9. `confirm '¿Iniciar la copia? [s/N]: '`; cualquier cosa distinta de `s`/`S`
   → "Operación cancelada.".

`run_backup` (no interactiva):

1. `mkdir` de la carpeta de respaldo y de `<nombre>/`; asigna
   `CURRENT_BACKUP_DIR` (para el aviso de interrupción).
2. `copy_tree` → si el código de salida ≠ 0:
   `ADVERTENCIA: la copia terminó con errores (código N); …`
3. `write_catalog` → `catalogo.txt`.
4. `tree_stats` del origen y de la copia; EXITOSA solo si coinciden cantidad
   **y** bytes **y** la copia terminó sin errores.
5. `sync`; limpia `CURRENT_BACKUP_DIR`.
6. `print_backup_summary`: origen, carpetas, catálogo, método, duración,
   conteos, resultado y el comando `umount` sugerido.

### Catálogo (`write_catalog`)

- Encabezado con origen y fecha de generación; luego una línea por archivo
  **y** directorio: `ruta_relativa<TAB>AAAA-MM-DD HH:MM:SS.fracción`.
- Se genera desde el **origen**, no desde la copia: refleja las fechas
  originales con precisión completa (FAT las redondea a 2 s).
- Registros NUL → `LC_ALL=C sort -z` (orden por bytes, estable entre
  configuraciones regionales) → `tr '\n\0' '?\n'`: un salto de línea dentro de
  un nombre se muestra como `?` y cada NUL se convierte en fin de línea.
- `|| true`: `find` devuelve 1 si encuentra un directorio ilegible aunque el
  catálogo se haya escrito; solo un fallo de la redirección (disco lleno, solo
  lectura) cuenta como error.

## Permisos

- Sin root, los archivos que el usuario no puede leer no se copian: `rsync`
  termina con código 23 y la verificación da **FALLIDA** (caso real
  verificado: `origen 4 / copia 3`). `tree_stats` sí cuenta el archivo
  ilegible en el origen porque `find` puede leer su tamaño (está en el
  directorio, no en el archivo).
- Una USB vfat montada por root pertenece a root salvo que se monte con
  `uid=`/`gid=` (o la monte el entorno de escritorio con `udisks`, que lo hace
  automáticamente). En la demostración se usó `uid=1000`.

## Casos borde (verificados)

| Caso | Resultado |
|---|---|
| Origen inexistente / es un archivo / ilegible | Error en español |
| Destino dentro del origen o igual al origen | Error |
| Destino hermano con prefijo común (`/x/a2` vs `/x/a`) | Aceptado |
| Destino inexistente, sin escritura o montado solo lectura | Error |
| Espacio insuficiente (`du -sb` vs. `df` avail) | Error |
| Opción de destino inválida o `c` | Error / "Operación cancelada." |
| Destino en `/` | Confirmación adicional |
| Dos copias en el mismo segundo | Segunda carpeta con sufijo `_1` |
| Destino ext4 | `rsync -a`; `diff -r` sin diferencias; enlaces simbólicos conservados |
| Destino vfat | `rsync -rt --modify-window=2`; enlaces omitidos ("skipping non-regular file") |
| Sin `rsync` | Copia con `cp -a` |
| USB simulada (`lsblk` falso con `TRAN=usb`) | Listada como `/dev/loopX (100M) montado en …` |
| Archivo ilegible como usuario normal | rsync código 23, verificación FALLIDA (origen 4 / copia 3) |
| vfat montado **sin** `utf8` y nombre con tilde (`vacío`) | El kernel rechaza el nombre (`EINVAL`) → FALLIDA |
| Ctrl+C / SIGTERM durante la copia | `ADVERTENCIA: la copia de seguridad quedó INCOMPLETA en: …`, salida 130 / 143 |

## Diferencias entre distribuciones / entornos

- WSL no expone USB físicas a Linux: no se detecta ninguna y se usa `m`. Para
  la demostración se creó una imagen vfat de 200 MB montada en
  `/mnt/usb_demo` con `mount -o loop,uid=1000,utf8`. Una imagen loop no
  aparece como USB (`TRAN` vacío, `RM=0`) — correcto.
- `rsync` no viene instalado en todas las imágenes; el respaldo con `cp`
  funciona en todas.
- En escritorios las USB se montan solas en `/media/$USER/…` o
  `/run/media/$USER/…` (Fedora); en servidores hay que montarlas a mano.

## Ejemplos reales

WSL Ubuntu 26.04, usuario normal.

**Copia exitosa a vfat.** Entrada: `5`, `/home/jarma/Documentos`, `m`,
`/mnt/usb_demo`, `s`.

```text
=== Copia de seguridad a memoria USB ===

ADVERTENCIA: sin privilegios de root los archivos no legibles por su usuario no se copiarán.

Dispositivos de bloque (lsblk -o NAME,RM,TRAN,SIZE,MOUNTPOINT):
NAME RM TRAN   SIZE MOUNTPOINT
sda   0      356.9M 
sdb   0      159.4M 
sdc   0          4G [SWAP]
sdd   0          1T /mnt/wslg/distro
sde   0          1T 
sdf   0      141.4M 

Destinos disponibles:
  (no se detectaron memorias USB montadas)
  m) Ingresar una ruta de destino manualmente
  c) Cancelar

Calculando el tamaño del origen...
Espacio requerido (du -sb): 3420019 bytes (3.3MiB)
Espacio disponible:         209489920 bytes (199.8MiB)

Origen:  /home/jarma/Documentos
Destino: /mnt/usb_demo/backup_Documentos_20261103_174740 (sistema de archivos: vfat)
ADVERTENCIA: destino FAT: no se conservan propietarios, permisos ni enlaces simbólicos.

Copiando archivos...
Generando catalogo.txt...
Verificando la copia...
Sincronizando discos (sync)...

=== Resumen de la copia de seguridad ===

  Origen:                /home/jarma/Documentos
  Carpeta de respaldo:   /mnt/usb_demo/backup_Documentos_20261103_174740
  Copia de archivos:     /mnt/usb_demo/backup_Documentos_20261103_174740/Documentos
  Catálogo:              /mnt/usb_demo/backup_Documentos_20261103_174740/catalogo.txt
  Método:                rsync -rt --modify-window=2
  Duración:              0 s
  Archivos regulares:    origen 4 / copia 4
  Bytes en archivos:     origen 3420019 / copia 3420019
  Verificación:          EXITOSA (cantidad y tamaño total coinciden)

El dispositivo NO fue desmontado. Para retirarlo con seguridad ejecute:
  umount "/mnt/usb_demo"
```

Contenido resultante:

```text
$ ls -R "/mnt/usb_demo/backup_Documentos_20261103_174740"
/mnt/usb_demo/backup_Documentos_20261103_174740:
Documentos
catalogo.txt

/mnt/usb_demo/backup_Documentos_20261103_174740/Documentos:
fotos
informes 2026

/mnt/usb_demo/backup_Documentos_20261103_174740/Documentos/fotos:
cumpleaños.png
viaje playa.jpg

/mnt/usb_demo/backup_Documentos_20261103_174740/Documentos/informes 2026:
datos & cifras.csv
informe Q3.txt

$ cat catalogo.txt
# Catálogo de la copia de seguridad de: /home/jarma/Documentos
# Generado: 2026-11-03 17:47:40
# ruta_relativa	fecha_hora_modificacion
fotos	2026-11-03 17:47:37.9792149290
fotos/cumpleaños.png	2026-11-03 17:47:37.9872166110
fotos/viaje playa.jpg	2026-11-03 17:47:37.9792149290
informes 2026	2026-11-03 17:47:37.9941119760
informes 2026/datos & cifras.csv	2026-11-03 17:47:37.9987184390
informes 2026/informe Q3.txt	2026-11-03 17:47:37.9941119760
```

**Destino dentro del origen.** Entrada: `5`, `/home/jarma/Documentos`, `m`,
`/home/jarma/Documentos/fotos` (bloque `lsblk` igual al anterior, omitido):

```text
=== Copia de seguridad a memoria USB ===

ADVERTENCIA: sin privilegios de root los archivos no legibles por su usuario no se copiarán.

Dispositivos de bloque (lsblk -o NAME,RM,TRAN,SIZE,MOUNTPOINT):
…
Destinos disponibles:
  (no se detectaron memorias USB montadas)
  m) Ingresar una ruta de destino manualmente
  c) Cancelar
ERROR: el destino no puede estar dentro del directorio de origen.
```

## Limitaciones

- `du -sb` mide tamaño aparente: no considera el desperdicio por clúster de
  FAT ni el límite de 4 GiB por archivo de vfat (un archivo mayor fallará al
  copiar y la verificación dará FALLIDA).
- FAT no conserva propietarios, permisos ni enlaces simbólicos; fechas con
  resolución de 2 s; prohíbe `: * ? " < > |` en nombres.
- La verificación compara cantidad y bytes totales, no el contenido.
- En el catálogo, un salto de línea en un nombre aparece como `?`.
- El script no desmonta la USB (requiere normalmente root y el usuario puede
  querer seguir usándola); muestra el comando `umount`.
- Si se interrumpe, la carpeta incompleta no se borra (se informa su ruta).

## Preguntas probables de la sustentación

**¿Cómo detectan que un disco es una memoria USB?**
`lsblk -dnpr -o NAME,TYPE,RM,HOTPLUG,TRAN`: se aceptan discos con
`TRAN=usb`, `RM=1` o `HOTPLUG=1`. Luego `findmnt --source` da dónde está
montado cada disco o partición. Si no se detecta nada (WSL, VM), se puede
escribir la ruta a mano.

**¿Por qué rsync y no cp?**
rsync informa con precisión qué falló (código 23 = transferencia parcial),
copia el contenido con la barra final sin ambigüedad y se adapta a FAT con
`-rt --modify-window=2`. Si no está instalado se usa `cp`.

**¿Por qué opciones distintas para FAT?**
FAT no tiene propietarios, permisos ni enlaces simbólicos. Con `-a`, rsync
intenta aplicarlos y puede terminar con errores (código 23) aunque los datos
se hayan copiado (comportamiento documentado; no se reprodujo en las
pruebas). Con `-rt` copia datos y fechas, que es lo que FAT puede guardar, y
`--modify-window=2` tolera la resolución de 2 s de sus fechas.

**¿Cómo evitan copiar un directorio dentro de sí mismo?**
Se comparan las rutas absolutas físicas (`pwd -P`, sin enlaces):
`"${dest}/" == "${src%/}/"*`. La barra final evita que `/home/ana2` se
considere dentro de `/home/ana`.

**¿Cómo verifican la copia y por qué no con `du`?**
Se cuentan los archivos regulares y se suman sus bytes en origen y copia. `du`
incluye el tamaño de directorios, que cambia entre ext4 y vfat, y difiere
entre implementaciones; daría falsos fallos.

**¿Para qué sirve `sync`?**
Las escrituras quedan primero en la caché de páginas del kernel; `sync` las
fuerza al dispositivo. Sin él, retirar la USB inmediatamente podría dejar
archivos incompletos.

**¿Qué pasa si se presiona Ctrl+C durante la copia?**
El trap de `INT` llama a `on_interrupt 130`, que informa la ruta de la copia
INCOMPLETA y sale con 130 (128 + SIGINT). El trap `EXIT` borra los temporales.
