# Herramienta de administración de sistemas en BASH

Proyecto final del curso **Sistemas Operacionales** — Universidad Icesi.
Autores: Jose Miguel Armas, Santiago Zapata.

`bash/sysadmin-tool.sh` es una herramienta interactiva de menú para el
administrador de un data center. Implementa las cinco opciones del enunciado:

1. Usuarios creados en el sistema y fecha/hora de su último inicio de sesión.
2. Sistemas de archivos/discos con tamaño y espacio libre **en bytes**.
3. Los diez archivos más grandes de un disco o sistema de archivos indicado
   por el usuario, con su ruta completa.
4. Memoria libre y swap en uso (bytes y porcentaje).
5. Copia de seguridad de un directorio a una memoria USB, con un catálogo de
   nombres de archivo y fecha de última modificación.

La versión en PowerShell se encuentra en [`powershell/sysadmin-tool.ps1`](powershell/sysadmin-tool.ps1)
y su documentación detallada está en [`powershell/README.md`](powershell/README.md).

Documentación detallada:

| Documento (Bash) | Documento (PowerShell) | Contenido |
|---|---|---|
| [`docs/bash/architecture.md`](docs/bash/architecture.md) | [`docs/powershell/architecture.md`](docs/powershell/architecture.md) | Estructura del script, funciones, convenciones, errores |
| [`docs/bash/option-1-users.md`](docs/bash/option-1-users.md) | [`docs/powershell/option-1-users.md`](docs/powershell/option-1-users.md) | Opción 1: usuarios y último login |
| [`docs/bash/option-2-filesystems.md`](docs/bash/option-2-filesystems.md) | [`docs/powershell/option-2-filesystems.md`](docs/powershell/option-2-filesystems.md) | Opción 2: sistemas de archivos y discos |
| [`docs/bash/option-3-largest-files.md`](docs/bash/option-3-largest-files.md) | [`docs/powershell/option-3-largest-files.md`](docs/powershell/option-3-largest-files.md) | Opción 3: diez archivos más grandes |
| [`docs/bash/option-4-memory.md`](docs/bash/option-4-memory.md) | [`docs/powershell/option-4-memory.md`](docs/powershell/option-4-memory.md) | Opción 4: memoria RAM y swap |
| [`docs/bash/option-5-backup.md`](docs/bash/option-5-backup.md) | [`docs/powershell/option-5-backup.md`](docs/powershell/option-5-backup.md) | Opción 5: copia de seguridad a USB |
| [`tests/README.md`](tests/README.md) | [`tests/powershell/README.md`](tests/powershell/README.md) | Suites de pruebas automatizadas (BATS para Bash y Pester para PowerShell) |

Cada documento de opción termina con preguntas probables de la sustentación y
su respuesta breve.

---

## Requisitos

- Linux con **bash ≥ 4.4**. Motivo: con `set -u`, bash < 4.4 trata la
  expansión de un arreglo vacío (`"${arr[@]}"`) como variable no definida y
  aborta; el script expande arreglos que pueden estar vacíos (por ejemplo, la
  lista de cuentas de sistema o `TMP_FILES`).
- Herramientas GNU/util-linux: `find -printf`, `df --output`, `findmnt`,
  `lsblk`. No funciona con BusyBox ni en macOS/BSD.

### Dependencias obligatorias

Son las de `REQUIRED_CMDS` en el script; `check_dependencies` las verifica al
arrancar y, si falta alguna, muestra `ERROR: … faltan comandos obligatorios: …`
y termina con código 1.

| Comando | Debian / Ubuntu | Fedora / Rocky (RHEL) |
|---|---|---|
| `getent` | `libc-bin` | `glibc-common` |
| `df`, `sort`, `head`, `tail`, `tr`, `wc`, `du`, `date`, `mktemp`, `basename`, `sync` | `coreutils` | `coreutils` |
| `find` | `findutils` | `findutils` |
| `awk` | `mawk` o `gawk` | `gawk` |
| `findmnt`, `lsblk` | `util-linux` | `util-linux` (la imagen base de Fedora no trae `lsblk`) |

`clear` (ncurses) es opcional: si no existe, simplemente no se limpia la
pantalla.

### Dependencias opcionales

| Comando | Uso | Si falta |
|---|---|---|
| `rsync` | Copia de la opción 5 | Se usa `cp -a` (o `cp -r --preserve=timestamps` en FAT) |
| `numfmt` (coreutils) | Tamaños legibles (`KiB`, `MiB`…) | Cálculo equivalente con `awk` |
| `lastlog2` | Último login (opción 1), 1.ª preferencia | Se intenta `lastlog` |
| `lastlog` (shadow-utils) | Último login, 2.ª preferencia | Se intenta `last` |
| `last` (util-linux o `wtmpdb`) | Último login, 3.ª preferencia | La columna muestra "No disponible" y se sugiere instalar `lastlog2` |

## Instalación

```bash
git clone https://github.com/josemiguelarmas/proyecto-final-so-armas-zapata.git
cd proyecto-final-so-armas-zapata
chmod +x bash/sysadmin-tool.sh     # el bit ya está en git (modo 100755)
```

Recomendado en Debian/Ubuntu:

```bash
sudo apt install rsync lastlog2
```

### Windows con WSL

```powershell
wsl --install -d Ubuntu
```

Dentro de Ubuntu: `sudo apt install lastlog2 rsync`. Notas:

- Ubuntu 26.04 no trae `lastlog` ni `last` por defecto; sin `lastlog2` la
  opción 1 muestra "No disponible".
- WSL no expone memorias USB físicas a Linux: en la opción 5 se usa el destino
  manual (`m`). Para la demostración se montó una imagen vfat de 200 MB con
  `mount -o loop,uid=1000,utf8` en `/mnt/usb_demo`.
- Clonar dentro del sistema de archivos de Linux (`~/…`) o mantener los finales
  de línea LF. El archivo `.gitattributes` fuerza `*.sh text eol=lf`: si git
  convirtiera el script a CRLF en Windows, bash fallaría con
  `$'\r': command not found`.

## Ejecución

```bash
./bash/sysadmin-tool.sh          # usuario normal: resultados parciales
sudo ./bash/sysadmin-tool.sh     # resultados completos
```

Sin root el script avisa al inicio
(`ADVERTENCIA: no se está ejecutando como root; …`): la opción 3 no puede leer
directorios protegidos y la opción 5 no copia archivos que el usuario no puede
leer. Se sale con `0`; también termina si la entrada estándar llega a EOF.

## Opciones y ejemplos reales

Los ejemplos se capturaron en WSL Ubuntu 26.04 como usuario normal (`jarma`)
pasando la entrada por una tubería. Por eso **no aparecen** los prompts de
`read -p` ni lo que se tecleó (bash solo muestra el prompt si la entrada es
una terminal); la secuencia de entrada se indica en cada caso. Después de cada
opción se envió Enter (pausa) y `0` (salir). Se omite el menú repetido (`…`).

### Menú y opción inválida — entrada: `abc`

```text
ADVERTENCIA: no se está ejecutando como root; algunas opciones pueden mostrar información incompleta.

========================================
  Herramienta de administración - DESKTOP-K1841JS
========================================
  1) Usuarios y último inicio de sesión
  2) Sistemas de archivos y discos
  3) Los diez archivos más grandes
  4) Memoria RAM y swap
  5) Copia de seguridad a USB
  0) Salir
========================================
ERROR: opción no válida: 'abc'. Ingrese un número entre 0 y 5.
…
Hasta luego.
```

### 1) Usuarios y último inicio de sesión — entrada: `1`, `1`

Pide si se listan solo humanos (root y UID ≥ 1000) o todas las cuentas.
Obtiene las cuentas con `getent passwd` y el último login con `lastlog2`,
`lastlog` o `last` (el primero que exista).

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
```

### 2) Sistemas de archivos y discos — entrada: `2`, Enter

`df -B1 --output=…` (bytes exactos), ocultando por defecto los
pseudo-sistemas de archivos, más `lsblk -b` para los discos físicos.

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
…
sdd  disk 1099511627776  0      Virtual Disk    
…
```

### 3) Diez archivos más grandes — entrada: `3`, `/usr`

Acepta un directorio/punto de montaje o un dispositivo de bloques (se
traduce a su punto de montaje con `findmnt`). Usa
`find -xdev -type f -printf '%s\t%p\0' | sort -z -rn | head -z -n 10`.

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
  …
 10          15125944     14.5MiB  /usr/lib/snapd/snap-bootstrap
```

### 4) Memoria RAM y swap — entrada: `4`

Lee `/proc/meminfo` (valores en KiB × 1024).

```text
=== Memoria RAM y swap ===

Memoria RAM (fuente: /proc/meminfo)
  Total (MemTotal):                16485855232 bytes     15.4GiB
  Libre (MemFree):                 13146951680 bytes     12.3GiB   79.75 %
  Disponible (MemAvailable):       15150551040 bytes     14.2GiB   91.90 %
  (Libre = memoria sin usar; Disponible = memoria utilizable sin recurrir a swap,
   incluye cachés que el kernel puede liberar.)

Swap
  Total (SwapTotal):                4294967296 bytes      4.0GiB
  Usada (Total - Free):                      0 bytes          0B    0.00 %
```

### 5) Copia de seguridad a USB — entrada: `5`, `/home/jarma/Documentos`, `m`, `/mnt/usb_demo`, `s`

Detecta memorias USB montadas (`lsblk` + `findmnt`) o acepta una ruta manual,
valida origen/destino/espacio, copia con `rsync`, genera `catalogo.txt`,
verifica y ejecuta `sync`.

```text
=== Copia de seguridad a memoria USB ===

ADVERTENCIA: sin privilegios de root los archivos no legibles por su usuario no se copiarán.

Dispositivos de bloque (lsblk -o NAME,RM,TRAN,SIZE,MOUNTPOINT):
…
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

Catálogo generado (`catalogo.txt`, separado por tabulador):

```text
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

Más ejemplos (dispositivo en la opción 3, todas las cuentas en la opción 1,
errores de la opción 5) en los documentos de cada opción.

## Decisiones de diseño

| Decisión | Por qué |
|---|---|
| `set -uo pipefail` **sin** `-e` | `-u` detecta variables mal escritas; `pipefail` hace que una tubería falle si falla cualquier etapa. `-e` no se usa porque en un menú interactivo un comando que falla (p. ej. `find` sin permisos) no debe cerrar el programa: cada función revisa sus errores y retorna 1, y el menú continúa. |
| `trap cleanup EXIT`, `trap 'on_interrupt 130' INT`, `trap 'on_interrupt 143' TERM` | Borra temporales siempre; ante Ctrl+C o SIGTERM avisa si quedó una copia incompleta y sale con 128 + número de señal. |
| Una función por opción + funciones auxiliares | Legibilidad, y permite que las pruebas BATS carguen el script con `source` y prueben funciones aisladas (el menú solo corre si `BASH_SOURCE[0] == $0`). |
| `getent passwd` en vez de leer `/etc/passwd` | Incluye usuarios de LDAP/NIS/SSSD según `/etc/nsswitch.conf`. |
| Detección en tiempo de ejecución de `lastlog2` → `lastlog` → `last` | Cada distribución trae una herramienta distinta; también se busca en `/usr/sbin` y `/sbin`. |
| Registros delimitados por NUL (`-printf …\0`, `sort -z`, `head -z`, `read -d ''`) | El NUL es el único byte que no puede aparecer en una ruta; soporta espacios, tabuladores y saltos de línea en nombres. |
| `df -B1 --output=…` y `/proc/meminfo` × 1024 | El enunciado pide **bytes**; se evita parsear salidas "humanas" (`-h`, `free -h`). |
| `LC_ALL=C` al ejecutar herramientas cuya salida se parsea | Formato de fechas, números y mensajes independiente del idioma del sistema. |
| `find -xdev` | "Un disco o filesystem": no descender a otros sistemas de archivos montados debajo. |
| Validar todo antes de escribir (opción 5) | No dejar copias a medias por errores previsibles (destino dentro del origen, sin espacio, solo lectura…). |
| Mensajes de error por `stderr` con prefijo `ERROR:`/`ADVERTENCIA:` | Separar diagnóstico de resultados; fácil de verificar en pruebas. |
| `clear` solo si la salida es una terminal (`[[ -t 1 ]]`) | No ensuciar con secuencias de escape la salida redirigida. |

Detalles en [`docs/bash/architecture.md`](docs/bash/architecture.md).

## Limitaciones conocidas

- **Último login**: depende de la herramienta instalada y de que exista su base
  de datos (`/var/lib/lastlog/lastlog2.db`, `/var/log/lastlog` o `wtmp`).
  `lastlog2`/`lastlog` guardan solo el último login; `last` lee `wtmp`, que
  puede haber sido rotado (entonces aparece "Nunca ha iniciado sesión").
- La heurística de "usuario humano" (root + UID ≥ 1000, excluyendo `nobody`
  65534) no lee `UID_MIN` de `/etc/login.defs`.
- Opción 2: la salida de `df` se separa por espacios; un **dispositivo**
  (columna SOURCE) con espacios rompería las columnas. Puntos de montaje con
  espacios sí funcionan.
- `printf` de bash rellena por bytes; el resumen de la opción 5 usa
  `print_field`, que cuenta caracteres. En una configuración regional que no
  sea UTF-8 las etiquetas con tildes quedan desalineadas.
- Opción 3: en un sistema de archivos grande recorrer todo con `find` es lento.
- Opción 5: `du -sb` mide el tamaño aparente; no considera el desperdicio por
  clúster de FAT ni el límite de 4 GiB por archivo de vfat.
- FAT/vfat no conserva propietarios, permisos ni enlaces simbólicos (se
  omiten), guarda fechas con resolución de 2 s y prohíbe caracteres como
  `: * ? " < > |`.
- La verificación compara cantidad y bytes totales de archivos regulares, no
  sumas de verificación del contenido. Verificación más fuerte, opcional:
  `rsync -rcn --itemize-changes ORIGEN/ DESTINO/`.
- En `catalogo.txt` un salto de línea dentro de un nombre se muestra como `?`.
- Requiere GNU `find` (`-printf`), GNU `df` (`--output`) y util-linux.
- En WSL no hay USB física: se usa destino manual.
- El script **no desmonta** la memoria; indica el comando `umount`.

## Estructura del repositorio

```text
.
├── bash/
│   └── sysadmin-tool.sh     # la herramienta (único script)
├── docs/
│   ├── bash/                # documentación técnica de Bash (arquitectura + opciones 1-5)
│   └── powershell/          # documentación técnica de PowerShell (arquitectura + opciones 1-5)
├── powershell/
│   ├── sysadmin-tool.ps1    # herramienta en PowerShell para Windows
│   └── README.md            # documentación de la versión PowerShell
├── tests/                   # suite BATS, run-tests.sh y README de pruebas
├── .gitattributes           # *.sh con LF (evita "$'\r': command not found")
├── .gitignore
└── README.md
```

## Pruebas

La suite automatizada (BATS, más ShellCheck) y cómo ejecutarla están en
[`tests/README.md`](tests/README.md).
