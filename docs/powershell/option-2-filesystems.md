# Opción 2 (PowerShell) — Sistemas de archivos y discos

## Requisito

> Desplegar los filesystems o discos conectados a la máquina. Incluir para cada
> disco su tamaño y la cantidad de espacio libre (en bytes).

Al igual que en la herramienta en Bash, se presentan ambas vistas: los
**sistemas de archivos / volúmenes montados** (con tamaño total y espacio
disponible en bytes) y los **discos físicos** conectados al equipo.

## Cmdlets y clases usados, y por qué

| Recurso | Uso | Por qué / alternativas descartadas |
|---|---|---|
| `Get-CimInstance Win32_LogicalDisk` | Tabla principal de sistemas de archivos montados | Entrega `DeviceID` (`C:`), `FileSystem` (`NTFS`, `FAT32`), `Size` y `FreeSpace` **directamente en bytes exactos** (`uint64`), además de `DriveType` y `VolumeName`. |
| `Get-CimInstance Win32_DiskDrive` | Tabla complementaria de discos físicos | Muestra el dispositivo físico (`\\.\PHYSICALDRIVE0`), `Size` en bytes, `InterfaceType` (`SCSI`, `NVMe`, `USB`) y `Model`, incluso si un disco no tiene particiones montadas. |

Alternativas descartadas:

- **`Get-PSDrive -PSProvider FileSystem`**: no informa el tipo de sistema de
  archivos (`NTFS`, `FAT32`, `exFAT`) sin consultas adicionales.
- **`Get-Volume`**: en versiones sin el servicio *Storage Management* activo
  puede fallar, mientras que `Win32_LogicalDisk` está disponible en todas las
  instalaciones de Windows.
- **`fsutil volume diskfree C:`**: requiere ejecutar un proceso externo por
  cada letra de unidad y parsear texto dependiente del idioma.

## Algoritmo (`Invoke-OptionFilesystems`)

1. Pregunta `¿Incluir unidades de red, ópticas o sin formato? [s/N]`.
   - Por defecto (Enter o `N`) filtra `DriveType` en `@(2, 3)` (`2` = disco
     removible/USB, `3` = disco fijo local) con tamaño definido (`$null -ne $d.Size`).
   - Si el usuario responde `s`/`S`, incluye también unidades de red (`4`),
     discos ópticos (`5`), discos RAM (`6`) y unidades sin formato (`RAW`).
2. Construye las filas con `DISPOSITIVO`, `TIPO`, `TOTAL (BYTES)`,
   `DISPONIBLE (BYTES)` y `MONTAJE (ETIQUETA)`.
3. Si no hay filas, informa `ERROR: no se encontró ningún sistema de archivos montado.`
4. Calcula el ancho dinámico de las columnas de texto con `Get-MaxLength` y
   deja 18 caracteres fijos para las columnas numéricas de bytes.
5. Consulta `Win32_DiskDrive` ordenado por `Index` y muestra la tabla de discos
   físicos conectados con su tamaño en bytes, bus y modelo.

## Columnas

| Columna | Propiedad en `Win32_LogicalDisk` | Significado |
|---|---|---|
| `DISPOSITIVO` | `DeviceID` | Identificador de volumen lógico (`C:`, `D:`) |
| `TIPO` | `FileSystem` | Sistema de archivos (`NTFS`, `FAT32`, `exFAT`, `ReFS`) |
| `TOTAL (BYTES)` | `Size` | Capacidad total del sistema de archivos en bytes |
| `DISPONIBLE (BYTES)` | `FreeSpace` | Espacio libre disponible en bytes |
| `MONTAJE (ETIQUETA)` | `DeviceID\ (VolumeName)` | Ruta raíz de montaje y etiqueta del volumen |

## Permisos

Tanto `Win32_LogicalDisk` como `Win32_DiskDrive` se pueden consultar con un
usuario estándar sin privilegios de Administrador.

## Casos borde (verificados)

| Caso | Comportamiento |
|---|---|
| Volumen sin etiqueta (`VolumeName` vacío) | Se muestra `(-)` en la columna de etiqueta |
| Unidad óptica sin disco insertado (`Size = $null`) | Oculta por defecto; si se elige `s`, muestra `RAW/N/A` y `0` bytes |
| Memoria USB conectada (`DriveType = 2`) | Incluida automáticamente en la vista por defecto junto a los discos fijos |

## Ejemplo real

Windows 11, usuario estándar. Entrada: `2`, `N`.

```text
=== Sistemas de archivos y discos ===

DISPOSITIVO  TIPO       TOTAL (BYTES)  DISPONIBLE (BYTES)  MONTAJE (ETIQUETA)
-----------------------------------------------------------------------------
C:           NTFS        510970032128        112249917440  C:\ (Windows)

Discos físicos (Win32_DiskDrive):
DISPOSITIVO             TAMAÑO (BYTES)  BUS   MODELO
\\.\PHYSICALDRIVE0        512105932800  SCSI  SAMSUNG MZVLQ512HALU-000H1
```

## Limitaciones

- Los volúmenes ocultos que no tienen letra de unidad asignada (como la
  partición EFI del sistema o la partición de recuperación de Windows) no
  aparecen en `Win32_LogicalDisk`; su espacio forma parte de la diferencia
  entre el tamaño de `Win32_DiskDrive` (`512,105,932,800` bytes) y el volumen
  `C:` (`510,970,032,128` bytes).

## Preguntas probables de la sustentación

**¿Por qué no coinciden el tamaño de `Win32_DiskDrive` y el de `Win32_LogicalDisk`?**  
`Win32_DiskDrive` reporta la capacidad física total del SSD/HDD
(`512,105,932,800` bytes), mientras que `Win32_LogicalDisk` reporta el tamaño
del sistema de archivos NTFS en la partición `C:` (`510,970,032,128` bytes),
descontando las particiones de arranque EFI, recuperación (WinRE) y metadatos.

**¿Por qué usar `Win32_LogicalDisk` en lugar de `Get-PSDrive`?**  
`Win32_LogicalDisk` provee directamente el tipo de sistema de archivos (`NTFS`,
`FAT32`, `exFAT`), la etiqueta del volumen (`VolumeName`), el tipo de unidad
(`DriveType`) y los valores exactos en bytes (`Size` y `FreeSpace`).

**¿Qué códigos de `DriveType` existen en Windows?**  
`2` = disco removible (memorias USB), `3` = disco fijo local, `4` = unidad de
red mapeada, `5` = unidad óptica (CD/DVD/ISO) y `6` = disco RAM. Por defecto se
muestran `2` y `3` porque corresponden a discos conectados localmente.
