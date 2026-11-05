# Opción 5 (PowerShell) — Copia de seguridad a memoria USB

## Requisito

> Hacer copia de seguridad (backup) de un directorio especificado a una memoria
> USB. Además de los archivos, se debe almacenar un catálogo que contenga los
> nombres de los archivos y su fecha de última modificación.

## Resultado en el destino

```text
<destino>\backup_<nombre>_AAAAmmdd_HHMMSS\
├── <nombre>\        # copia del contenido del directorio de origen
└── catalogo.txt     # ruta relativa <TAB> fecha y hora de modificación
```

- El nombre de la carpeta incluye la marca de tiempo (`yyyyMMdd_HHmmss`) para
  no sobrescribir copias previas; si ya existe una carpeta con ese nombre en el
  mismo segundo, `Get-UniqueBackupDir` agrega `_1`, `_2`, etc.
- `catalogo.txt` se almacena junto a la carpeta `<nombre>\` (y no dentro de
  ella) para no alterar los archivos respaldados ni el conteo de verificación.

## Herramientas y clases usadas, y por qué

| Recurso | Uso | Por qué / alternativas descartadas |
|---|---|---|
| `Win32_LogicalDisk` (`DriveType = 2`) + asociación `Win32_DiskDrive` (`InterfaceType = 'USB'`) | Detección de memorias y discos USB (`Get-UsbLogicalDisks`) | Las memorias flash USB reportan `DriveType = 2` (Removible), pero muchos discos duros y SSD externos por USB reportan `DriveType = 3` (Fijo). Consultar también `Win32_DiskDrive` por `InterfaceType = 'USB'` detecta ambos casos. |
| `[System.IO.DriveInfo]` | Espacio disponible (`AvailableFreeSpace`), formato (`DriveFormat`) y estado (`IsReady`) | Consulta directa a la API Win32 del volumen en bytes exactos. |
| `robocopy.exe` | Copia del árbol de archivos (`Copy-BackupTree`) | Herramienta nativa de administración en Windows Server/Client: preserva marcas de tiempo de archivos y directorios (`/COPY:DT /DCOPY:T`), omite bucles por *junctions* (`/XJ`), soporta rutas de más de 260 caracteres y ofrece `/FFT` para sistemas FAT. Si no estuviera disponible, usa `Copy-Item -Recurse -Force`. |
| `[System.IO.DirectoryInfo]` | Generación de `catalogo.txt` y verificación (`Get-TreeStats`) | Obtiene rutas relativas y `LastWriteTime` con resolución de fracciones de segundo (`yyyy-MM-dd HH:mm:ss.fffffff`) en una sola pasada. |
| `Write-VolumeCache` | Sincronización de caché de disco | Equivalente en Windows a `sync` de Linux: vacía la caché de escritura del volumen antes de retirar la unidad. |

## Algoritmo

### Fase 1: Validaciones antes de escribir (`Invoke-OptionBackup`)

1. Advierte si no se está ejecutando como Administrador.
2. Solicita el directorio de origen (`Read-UserPath`) y lo valida con
   `Resolve-ExistingDirectory`:
   - no existe → `ERROR: el directorio de origen '…' no existe.`
   - no es un directorio → `ERROR: '…' no es un directorio.`
   - sin permiso de lectura → `ERROR: no tiene permiso de lectura sobre '…'.`
3. `Select-BackupDestination` muestra las unidades detectadas, lista las
   memorias USB montadas (`1..N`) y ofrece `m` (ingresar ruta manualmente) o
   `c` (cancelar).
4. Valida que el destino exista y sea un directorio, y ejecuta
   `Test-BackupDestination`:
   - Verifica que pertenezca a una unidad montada y lista (`DriveInfo.IsReady`).
   - Comprueba que **no esté dentro del directorio de origen** comparando las
     rutas absolutas con barra final (`\`) de forma insensible a
     mayúsculas/minúsculas (`OrdinalIgnoreCase`), evitando que `C:\datos2` sea
     tomado como subdirectorio de `C:\datos` y rechazando cuando destino =
     origen (`ERROR: el destino no puede estar dentro del directorio de origen.`).
   - Prueba permiso real de escritura creando y borrando un archivo sonda
     temporal en el destino.
   - Si el origen y el destino están en la misma unidad, muestra una
     advertencia.
5. Si el destino está en la unidad del sistema (`C:\`), advierte que no es una
   unidad USB externa y exige confirmación explícita (`¿Seguro que desea usar este destino? [s/N]`).
6. Calcula el tamaño total de los archivos regulares del origen (`Get-TreeStats`)
   y lo compara contra `DriveInfo.AvailableFreeSpace` (`Test-FreeSpace`). Si no
   cabe → `ERROR: espacio insuficiente en el destino.`
7. Muestra el resumen previo (origen, carpeta de destino y sistema de archivos;
   si es FAT/FAT32/exFAT advierte sus limitaciones) y solicita confirmación
   final (`¿Iniciar la copia? [s/N]`).

### Fase 2: Ejecución, catálogo y verificación (`Invoke-BackupRun`)

1. Crea `backup_<nombre>_<fecha>` y la subcarpeta `<nombre>`.
2. Ejecuta `Copy-BackupTree` (`robocopy /E /COPY:DT /DCOPY:T /XJ /R:0 /W:0`,
   añadiendo `/FFT` si el destino es FAT). En `robocopy`, los códigos de salida
   `0` y `1` indican copia exitosa sin fallos; códigos `> 1` generan una
   advertencia.
3. Genera `catalogo.txt` (`Write-BackupCatalog`) desde el directorio de origen,
   ordenado con `StringComparer::Ordinal` y codificado en UTF-8 con BOM para
   que se visualice correctamente tanto en PowerShell 5.1 como en editores de
   texto.
4. Verifica la copia comparando cantidad de archivos regulares y suma de bytes
   entre origen y copia (`Get-TreeStats`).
5. Intenta vaciar la caché de volumen con `Write-VolumeCache` y muestra el
   resumen completo (`Write-BackupSummary`).

## Casos borde (verificados)

| Caso | Resultado |
|---|---|
| Origen inexistente o es un archivo | Error en español antes de pedir destino |
| Destino igual al origen o subcarpeta del origen | `ERROR: el destino no puede estar dentro del directorio de origen.` |
| Destino en la unidad del sistema (`C:\`) | Advertencia + confirmación adicional obligatoria |
| Destino sin permisos de escritura o de solo lectura | Detectado por el archivo sonda antes de iniciar la copia |
| Espacio libre insuficiente | `ERROR: espacio insuficiente en el destino.` |
| Destino FAT32 / exFAT | Advertencia sobre ACL/symlinks y adición automática de `/FFT` en `robocopy` |

## Ejemplo real

Windows 11, usuario estándar. Respaldo de la carpeta `docs` hacia un directorio
de prueba.

```text
=== Copia de seguridad a memoria USB ===

ADVERTENCIA: sin privilegios de Administrador los archivos no legibles por su usuario no se copiarán.

Unidades de almacenamiento (Win32_LogicalDisk):
UNIDAD    TIPO        FS              TAMAÑO  ETIQUETA
C:\       Fijo        NTFS          475.9GiB  Windows

Destinos disponibles:
  (no se detectaron memorias USB montadas)
  m) Ingresar una ruta de destino manualmente
  c) Cancelar
ADVERTENCIA: el destino está en la misma unidad que el origen; la copia no protege ante una falla de ese disco.
ADVERTENCIA: el destino está en la unidad del sistema (C:\), no en una unidad USB externa.

Calculando el tamaño del origen...
Espacio requerido:  58617 bytes (57.2KiB)
Espacio disponible: 112642621440 bytes (104.9GiB)

Origen:  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\docs
Destino: C:\Users\gigi\AppData\Local\Temp\usb_demo_ps_test\backup_docs_20261105_120621 (sistema de archivos: NTFS)

Copiando archivos...
Generando catalogo.txt...
Verificando la copia...
Sincronizando caché de disco...

=== Resumen de la copia de seguridad ===

  Origen:                C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\docs
  Carpeta de respaldo:   C:\Users\gigi\AppData\Local\Temp\usb_demo_ps_test\backup_docs_20261105_120621
  Copia de archivos:     C:\Users\gigi\AppData\Local\Temp\usb_demo_ps_test\backup_docs_20261105_120621\docs
  Catálogo:              C:\Users\gigi\AppData\Local\Temp\usb_demo_ps_test\backup_docs_20261105_120621\catalogo.txt
  Método:                robocopy /E /COPY:DT /DCOPY:T /XJ /R:0 /W:0 /NP /NFL /NDL /NJH /NJS
  Duración:              3 s
  Archivos regulares:    origen 6 / copia 6
  Bytes en archivos:     origen 58617 / copia 58617
  Verificación:          EXITOSA (cantidad y tamaño total coinciden)

El dispositivo NO fue expulsado. Use 'Quitar hardware de forma segura' antes de retirar C:\.
```

Contenido de `catalogo.txt`:

```text
# Catálogo de la copia de seguridad de: C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\docs
# Generado: 2026-11-05 12:06:21
# ruta_relativa	fecha_hora_modificacion
architecture.md	2026-11-05 11:20:02.0887812
option-1-users.md	2026-11-05 11:20:02.0907721
option-2-filesystems.md	2026-11-05 11:20:02.0924615
option-3-largest-files.md	2026-11-05 11:20:02.0934071
option-4-memory.md	2026-11-05 11:20:02.0959419
option-5-backup.md	2026-11-05 11:20:02.0978894
```

## Preguntas probables de la sustentación

**¿Cómo detecta el script tanto una memoria USB común como un disco duro/SSD externo por USB?**  
Combinando dos criterios: `Win32_LogicalDisk` con `DriveType = 2` (unidades
removibles tipo pendrive) y la navegación de asociaciones CIM desde
`Win32_DiskDrive` (`InterfaceType = 'USB'`) hacia `Win32_DiskPartition` y
`Win32_LogicalDisk` para discos externos USB que Windows clasifica con
`DriveType = 3`.

**¿Por qué en `robocopy` se evalúa `$LASTEXITCODE -gt 1` como error y no `$LASTEXITCODE -ne 0`?**  
Porque `robocopy` usa una máscara de bits en su código de retorno: `0` significa
"no había archivos que copiar" y `1` significa "se copiaron uno o más archivos
con éxito". Códigos mayores contienen bits de archivos extra, discrepancias o
errores de copia (`>= 8`).

**¿Por qué la comparación de si el destino está dentro del origen es insensible a mayúsculas/minúsculas (`OrdinalIgnoreCase`)?**  
Porque en Windows los sistemas de archivos NTFS, FAT32 y exFAT son
*case-insensitive* por defecto: `C:\Datos\Sub` y `c:\datos\sub` apuntan al
mismo directorio físico.
