# Herramienta de administración de sistemas en PowerShell

Proyecto final del curso **Sistemas Operacionales** — Universidad Icesi.  
Autores: Jose Miguel Armas, Santiago Zapata.

`powershell/sysadmin-tool.ps1` es la implementación nativa para Windows en
PowerShell de la herramienta interactiva de menú para el administrador de un
data center. Implementa las cinco opciones del enunciado con la misma interfaz,
validaciones y formato que `bash/sysadmin-tool.sh`:

1. Usuarios creados en el sistema y fecha/hora de su último inicio de sesión.
2. Sistemas de archivos/discos con tamaño y espacio libre **en bytes**.
3. Los diez archivos más grandes de un disco o directorio indicado por el
   usuario, con su ruta completa.
4. Memoria libre y swap (archivo de paginación) en uso (bytes y porcentaje).
5. Copia de seguridad de un directorio a una memoria USB, con un catálogo de
   nombres de archivo y fecha de última modificación.

Documentación detallada de PowerShell en `docs/powershell/`:

| Documento | Contenido |
|---|---|
| [`../docs/powershell/architecture.md`](../docs/powershell/architecture.md) | Estructura del script, funciones, convenciones y manejo de errores |
| [`../docs/powershell/option-1-users.md`](../docs/powershell/option-1-users.md) | Opción 1: usuarios y último login |
| [`../docs/powershell/option-2-filesystems.md`](../docs/powershell/option-2-filesystems.md) | Opción 2: sistemas de archivos y discos |
| [`../docs/powershell/option-3-largest-files.md`](../docs/powershell/option-3-largest-files.md) | Opción 3: diez archivos más grandes |
| [`../docs/powershell/option-4-memory.md`](../docs/powershell/option-4-memory.md) | Opción 4: memoria RAM y swap |
| [`../docs/powershell/option-5-backup.md`](../docs/powershell/option-5-backup.md) | Opción 5: copia de seguridad a USB |
| [`../tests/powershell/README.md`](../tests/powershell/README.md) | Suite de pruebas automatizadas en Pester (`tests/powershell/`) |

---

## Requisitos

- Windows 10 / 11 o Windows Server 2016+ con **Windows PowerShell ≥ 5.1** o
  **PowerShell 7+ (`pwsh`)**.
- Módulos estándar incluidos en Windows:
  - `CimCmdlets` (`Get-CimInstance`, `Get-CimAssociatedInstance`)
  - `Microsoft.PowerShell.LocalAccounts` (`Get-LocalUser`, con respaldo
    automático en `Win32_UserAccount` / `Win32_NetworkLoginProfile` vía CIM)
  - `robocopy.exe` (incluido en Windows; con respaldo en `Copy-Item -Recurse`)

---

## Ejecución

Desde una terminal de PowerShell en la raíz del repositorio:

```powershell
# Ejecución como usuario estándar (muestra advertencia al inicio)
powershell -ExecutionPolicy Bypass -File .\powershell\sysadmin-tool.ps1

# Ejecución recomendada (consola de PowerShell como Administrador)
.\powershell\sysadmin-tool.ps1
```

Si la política de ejecución de la sesión bloquea scripts locales, también se
puede habilitar temporalmente solo para el proceso actual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\powershell\sysadmin-tool.ps1
```

---

## Detalle técnico por opción

### 1) Usuarios y último inicio de sesión (`Invoke-OptionUsers`)

- **Obtención de cuentas:** Usa `Get-LocalUser` (base SAM local) y como
  respaldo `Get-CimInstance Win32_UserAccount -Filter "LocalAccount = True"` +
  `Win32_NetworkLoginProfile`.
- **Clasificación por RID (Relative Identifier):** El último componente del SID
  (`S-1-5-21-...-<RID>`) cumple el rol equivalente al UID en Linux:
  - `RID == 500` (`Administrador` integrado) y `RID >= 1000` (cuentas creadas
    en el sistema y habilitadas) se clasifican como **Usuarios humanos**.
  - `RID 501` (`Invitado`), `503` (`DefaultAccount`), `504`
    (`WDAGUtilityAccount`) y cuentas deshabilitadas se clasifican como
    **Cuentas de sistema / integradas**.
- **Último login:** Propiedad `LastLogon`. Si es `$null` o anterior a 1970, se
  muestra `Nunca ha iniciado sesión`.

```text
=== Usuarios del sistema y último inicio de sesión ===

  1) Solo usuarios humanos (Administrador RID 500 y cuentas activas RID >= 1000)
  2) Todas las cuentas locales (humanas, integradas y de sistema)

Fuente del último inicio de sesión: Get-LocalUser (SAM local)

USUARIOS HUMANOS (4)
USUARIO                       RID  FECHA      HORA    
-------                       ---  -----      ----    
Administrador                 500  2021-03-16 08:59:07
CodexSandboxOffline          1039  Nunca ha iniciado sesión
CodexSandboxOnline           1040  Nunca ha iniciado sesión
gigi                         1032  2026-11-05 10:53:25

CUENTAS DE SISTEMA / INTEGRADAS (3)
USUARIO                       RID  FECHA      HORA    
-------                       ---  -----      ----    
DefaultAccount                503  Nunca ha iniciado sesión
Invitado                      501  Nunca ha iniciado sesión
WDAGUtilityAccount            504  Nunca ha iniciado sesión
```

### 2) Sistemas de archivos y discos (`Invoke-OptionFilesystems`)

- **Volúmenes montados:** Consulta `Get-CimInstance Win32_LogicalDisk`. Sus
  propiedades `Size` y `FreeSpace` vienen directamente en **bytes exactos**.
  Por defecto muestra discos fijos (`DriveType = 3`) y removibles
  (`DriveType = 2`); opcionalmente incluye unidades de red (`4`), ópticas (`5`)
  y RAMDisk (`6`).
- **Discos físicos:** Consulta `Get-CimInstance Win32_DiskDrive` mostrando el
  dispositivo físico (`\\.\PHYSICALDRIVE0`), tamaño en bytes, tipo de bus
  (`NVMe`, `SCSI`, `SATA`, `USB`) y modelo.

```text
=== Sistemas de archivos y discos ===

DISPOSITIVO  TIPO       TOTAL (BYTES)  DISPONIBLE (BYTES)  MONTAJE (ETIQUETA)
-----------------------------------------------------------------------------
C:           NTFS        510970032128        112249917440  C:\ (Windows)

Discos físicos (Win32_DiskDrive):
DISPOSITIVO             TAMAÑO (BYTES)  BUS   MODELO
\\.\PHYSICALDRIVE0        512105932800  SCSI  SAMSUNG MZVLQ512HALU-000H1
```

### 3) Los diez archivos más grandes (`Invoke-OptionLargestFiles`)

- **Resolución de entrada (`Resolve-SearchPath`):** Acepta letras de unidad
  (`C`, `C:`, `C:\`) o rutas de directorio absolutas/relativas (incluyendo `~`).
- **Recorrido sin cruzar volúmenes:** Recorre el árbol iterativamente con una
  pila (`Stack[string]`) y `[System.IO.DirectoryInfo]`, omitiendo directorios y
  archivos con el atributo `ReparsePoint` (enlaces simbólicos, *junctions* y
  puntos de montaje de otros volúmenes, equivalente a `find -xdev` en Linux).
- **Manejo de permisos:** Si un directorio lanza `UnauthorizedAccessException`
  o `IOException`, incrementa el contador de errores sin abortar el recorrido y
  al final muestra una advertencia con el total de rutas inaccesibles.

```text
=== Los diez archivos más grandes ===


Buscando en: C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata
Nota: no es la raíz de la unidad; pertenece al sistema de archivos montado en C:\.
Se busca solo dentro de esta ruta, sin cruzar enlaces simbólicos ni puntos de montaje.
ADVERTENCIA: sin privilegios de Administrador algunos directorios pueden no ser accesibles.
Esto puede tardar en sistemas de archivos grandes...

  #             BYTES     LEGIBLE  RUTA
  1             76021     74.2KiB  C:\...\proyecto-final-so-armas-zapata\.git\objects\pack\pack-b66cc49cfe535ddad7e9f272c1239ac314978039.pack
  2             36068     35.2KiB  C:\...\proyecto-final-so-armas-zapata\bash\sysadmin-tool.sh
  3             24724     24.1KiB  C:\...\proyecto-final-so-armas-zapata\powershell\sysadmin-tool.ps1
  ...
```

### 4) Memoria RAM y swap (`Invoke-OptionMemory`)

- **Fuente:** `Get-CimInstance Win32_OperatingSystem`.
- **Conversión a bytes:** `TotalVisibleMemorySize`, `FreePhysicalMemory`,
  `SizeStoredInPagingFiles` y `FreeSpaceInPagingFiles` se entregan en **KiB**;
  se multiplican por `1024L` (`[int64]`) para obtener bytes exactos sin
  desbordamiento de 32 bits.
- **Swap / Archivo de paginación:** `SwapUsada = SizeStoredInPagingFiles - FreeSpaceInPagingFiles`.
  Si `SizeStoredInPagingFiles == 0`, informa que no hay archivo de paginación
  configurado evitando la división por cero.

```text
=== Memoria RAM y swap ===

Memoria RAM (fuente: Win32_OperatingSystem)
  Total (VisibleMemory):            8355172352 bytes      7.8GiB
  Libre (FreePhysical):             1242222592 bytes      1.2GiB   14.87 %
  (FreePhysicalMemory representa la memoria RAM física inmediatamente disponible
   sin necesidad de escribir en el archivo de paginación.)

Swap / Archivo de paginación
  Total (PagingFiles):             20401094656 bytes     19.0GiB
  Usada (Total - Free):             1866293248 bytes      1.7GiB    9.15 %
```

### 5) Copia de seguridad a memoria USB (`Invoke-OptionBackup`)

- **Detección de USB (`Get-UsbLogicalDisks`):** Identifica unidades con
  `DriveType = 2` (removibles) y unidades fijas (`DriveType = 3`) asociadas por
  CIM (`Win32_DiskDrive` → `Win32_DiskPartition` → `Win32_LogicalDisk`) a un
  disco físico con `InterfaceType = 'USB'` (caso común en discos duros/SSD
  externos por USB). También ofrece ingreso manual (`m`) o cancelar (`c`).
- **Validaciones antes de escribir:**
  - Origen existe, es directorio y tiene permisos de lectura.
  - Destino existe, es directorio, tiene permiso efectivo de escritura y **no
    está dentro del directorio de origen** (comparación insensible a
    mayúsculas/minúsculas con barra final `\`).
  - Advertencia y confirmación explícita si el destino está en la unidad del
    sistema (`C:\`).
  - Verificación de espacio libre (`DriveInfo.AvailableFreeSpace` vs suma de
    bytes del origen).
- **Copia, catálogo y verificación:**
  - Copia con `robocopy /E /COPY:DT /DCOPY:T /XJ` (agregando `/FFT` si el
    destino es FAT/FAT32/exFAT para tolerar la ventana de 2 segundos en
    timestamps).
  - Genera `catalogo.txt` con las rutas relativas y su fecha de última
    modificación (`yyyy-MM-dd HH:mm:ss.fffffff`) ordenadas lexicográficamente.
  - Compara cantidad de archivos regulares y total de bytes entre origen y
    copia, sincroniza caché (`Write-VolumeCache`) y muestra el resumen.

---

## Preguntas probables de la sustentación

**¿Cómo se distingue una cuenta humana de una de sistema en Windows?**  
Por el **RID** (último bloque numérico del SID de la cuenta): `RID 500` es el
Administrador integrado y `RID >= 1000` son las cuentas creadas por usuarios o
administradores; cuentas como `DefaultAccount` (`503`), `Invitado` (`501`) o
`WDAGUtilityAccount` (`504`) son cuentas integradas del sistema.

**¿Por qué usar `[System.IO.DirectoryInfo]` en lugar de `Get-ChildItem -Recurse` en la opción 3?**  
En Windows PowerShell 5.1, `Get-ChildItem -Recurse` puede seguir puntos de
reanálisis (*junctions* o montajes de otros volúmenes) y es considerablemente
más lento en discos grandes. El recorrido iterativo con `DirectoryInfo` permite
omitir explícitamente cualquier `ReparsePoint` (equivalente a `find -xdev`) y
contabilizar con exactitud cada directorio sin permisos.

**¿En qué unidades devuelve la memoria `Win32_OperatingSystem`?**  
En **KiB** (bloques de 1024 bytes), aunque la documentación antigua de WMI los
llame "kilobytes". Por eso se multiplican por `1024L` usando enteros de 64 bits
(`[int64]`).

**¿Por qué se usa `/FFT` en `robocopy` cuando el destino es FAT32?**  
Porque los sistemas de archivos FAT almacenan la hora de modificación con una
resolución de 2 segundos, mientras que NTFS usa intervalos de 100 nanosegundos.
`/FFT` indica a `robocopy` que asuma tiempos FAT con tolerancia de 2 segundos.
