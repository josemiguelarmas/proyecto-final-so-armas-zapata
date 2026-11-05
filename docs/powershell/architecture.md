# Arquitectura de `powershell/sysadmin-tool.ps1`

Un único script (~970 líneas), sin archivos auxiliares externos. Textos al
usuario en español; identificadores (verbos aprobados de PowerShell) y
comentarios en inglés.

## 1. Secciones del script

| Orden | Sección | Contenido |
|---|---|---|
| 1 | Cabecera y directivas | `#Requires -Version 5.1`, ayuda basada en comentarios, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, codificación UTF-8 |
| 2 | Constantes y estado de script | Variables `$script:...` (RIDs, tipos de disco, estado compartido) |
| 3 | *Generic helpers* | Mensajes a stdout/stderr, lectura de entrada, formato de bytes y porcentajes |
| 4 | *Startup checks* | `Test-Dependencies` |
| 5 | *Option 1* … *Option 5* | Una sección modular por cada opción del menú |
| 6 | *Menu and entry point* | `Show-Menu`, `Start-SysAdminTool` |
| 7 | Guarda de ejecución | Ejecuta `Start-SysAdminTool` solo si `$MyInvocation.InvocationName -ne '.'` (permite *dot-sourcing* en pruebas) |

`#Requires -Version 5.1` garantiza que el motor de PowerShell verifique la
versión mínima antes de ejecutar cualquier instrucción.

## 2. Variables de alcance de script (`$script:`)

Constantes de configuración:

| Nombre | Valor | Uso |
|---|---|---|
| `$script:SCRIPT_NAME` | Nombre del archivo (`sysadmin-tool.ps1`) | Prefijo en mensajes de error de dependencias |
| `$script:ADMIN_RID` | `500` | RID de la cuenta integrada `Administrador` (`S-1-5-21-...-500`) |
| `$script:HUMAN_RID_MIN` | `1000` | Umbral de RID para cuentas de usuario creadas en el sistema |
| `$script:FIXED_DRIVE_TYPES` | `@(2, 3)` | Tipos de unidad en `Win32_LogicalDisk` mostrados por defecto en la opción 2 (2 = Removible, 3 = Disco fijo local) |

Estado mutable compartido entre funciones auxiliares:

| Nombre | Escrita por | Significado |
|---|---|---|
| `$script:LOGIN_SOURCE` | `Get-LocalUserRecords` | Fuente usada para consultar los usuarios y su último login (`Get-LocalUser` o CIM) |
| `$script:COPY_METHOD` | `Copy-BackupTree` | Comando e interruptores empleados al copiar en la opción 5 (`robocopy ...` o `Copy-Item ...`) |

## 3. Funciones

### Auxiliares genéricas

| Función | Propósito |
|---|---|
| `Write-ErrorMsg` | Imprime `ERROR: …` por `stderr` (`[Console]::Error.WriteLine`) |
| `Write-WarningMsg` | Imprime `ADVERTENCIA: …` por `stderr` (`[Console]::Error.WriteLine`) |
| `Write-Header` | Imprime título `=== … ===` |
| `Write-Field` | Imprime par `"  etiqueta   valor"` alineado a 22 caracteres |
| `Clear-ScreenSafe` | Llama a `Clear-Host` solo si la salida estándar no está redirigida (`-not [Console]::IsOutputRedirected`) |
| `Wait-Pause` | `"Presione Enter para volver al menú..."` |
| `Test-IsAdmin` | Evalúa si el token actual pertenece a `[Security.Principal.WindowsBuiltInRole]::Administrator` |
| `Warn-IfNotAdmin` | Muestra advertencia si no se ejecuta como Administrador |
| `Read-UserInput` | Lee una línea desde consola interactiva (`Read-Host`) o desde `stdin` redirigido (`[Console]::In.ReadLine()`) |
| `Read-UserPath` | Lee una ruta y expande `~` o `~\` inicial hacia `$HOME` |
| `Confirm-Action` | Pregunta `[s/N]`; devuelve `$true` solo con `s` o `S`, en otro caso imprime `"Operación cancelada."` |
| `Format-HumanSize` | Convierte bytes a unidades binarias IEC (`B`, `KiB`, `MiB`, `GiB`, `TiB`, `PiB`) con `InvariantCulture` |
| `Format-Percentage` | Calcula porcentaje con 2 decimales (`0.00` si el total es `<= 0`) usando `InvariantCulture` |
| `Get-MaxLength` | Calcula el largo máximo de un arreglo de cadenas para alinear tablas dinámicamente |
| `Test-Dependencies` | Verifica la disponibilidad de `Get-CimInstance`, `Get-ChildItem`, `Copy-Item` y `Get-FileHash` |

### Opción 1 — usuarios ([detalle](option-1-users.md))

| Función | Propósito |
|---|---|
| `Get-AccountRid` | Extrae el RID numérico final de un SID (`S-1-5-21-...-RID`) |
| `Test-IsHumanAccount` | `Rid == 500` o (`Rid >= 1000` y cuenta habilitada) |
| `Get-LocalUserRecords` | Obtiene cuentas y último login con `Get-LocalUser` o respaldo CIM (`Win32_UserAccount` + `Win32_NetworkLoginProfile`) |
| `Write-UsersTable` | Imprime tabla alineada `USUARIO / RID / FECHA / HORA` |
| `Invoke-OptionUsers` | Flujo interactivo de la opción 1 |

### Opción 2 — sistemas de archivos ([detalle](option-2-filesystems.md))

| Función | Propósito |
|---|---|
| `Get-DriveTypeName` | Traduce el código `DriveType` de WMI/CIM a texto (`Removible`, `Fijo`, `Red`, `Óptico`, `RAMDisk`) |
| `Invoke-OptionFilesystems` | Tabla de volúmenes (`Win32_LogicalDisk`) en bytes + discos físicos (`Win32_DiskDrive`) |

### Opción 3 — archivos más grandes ([detalle](option-3-largest-files.md))

| Función | Propósito |
|---|---|
| `Resolve-SearchPath` | Normaliza letras de unidad (`C` / `C:` → `C:\`), valida existencia, tipo directorio y permisos |
| `Invoke-OptionLargestFiles` | Recorrido iterativo con `Stack[string]` y `DirectoryInfo` sin cruzar `ReparsePoint`, top 10 por `Length` |

### Opción 4 — memoria ([detalle](option-4-memory.md))

| Función | Propósito |
|---|---|
| `Write-MemoryLine` | Imprime línea formateada con etiqueta, bytes, tamaño legible y porcentaje |
| `Invoke-OptionMemory` | Consulta `Win32_OperatingSystem`, multiplica KiB × 1024 y calcula uso de RAM y archivo de paginación |

### Opción 5 — copia de seguridad ([detalle](option-5-backup.md))

| Función | Propósito |
|---|---|
| `Get-UsbLogicalDisks` | Detecta unidades con `DriveType = 2` o asociadas por CIM a un disco físico USB (`InterfaceType = 'USB'`) |
| `Select-BackupDestination` | Menú de destinos: USB detectadas, `m` ruta manual, `c` cancelar |
| `Resolve-ExistingDirectory` | Valida que origen/destino exista, sea directorio y permita lectura |
| `Test-BackupDestination` | Verifica unidad montada, escritura efectiva (archivo sonda) y que el destino no esté dentro del origen |
| `Get-TreeStats` | Cuenta archivos regulares y suma sus tamaños en bytes |
| `Test-FreeSpace` | Compara bytes requeridos contra `DriveInfo.AvailableFreeSpace` |
| `Test-IsFatFilesystem` | Detecta `FAT`, `FAT16`, `FAT32`, `VFAT`, `EXFAT` |
| `Get-UniqueBackupDir` | Añade sufijo `_1`, `_2`… si la carpeta de backup ya existe |
| `Copy-BackupTree` | Ejecuta `robocopy` (con `/FFT` en FAT) o respaldo `Copy-Item -Recurse` |
| `Write-BackupCatalog` | Genera `catalogo.txt` ordenado por ruta relativa con timestamp de última modificación |
| `Write-BackupSummary` | Imprime resumen completo de la copia y aviso de extracción segura |
| `Invoke-BackupRun` | Crea carpetas, copia, genera catálogo, verifica conteos, sincroniza caché (`Write-VolumeCache`) |
| `Invoke-OptionBackup` | Flujo interactivo y validaciones previas de la opción 5 |

### Menú y entrada

| Función | Propósito |
|---|---|
| `Show-Menu` | Imprime el menú principal con `$env:COMPUTERNAME` |
| `Start-SysAdminTool` | Verifica dependencias, advierte si no es Administrador y ejecuta el bucle principal |

## 4. Flujo de `Start-SysAdminTool`

```text
Start-SysAdminTool
 ├─ Test-Dependencies (si falla → exit 1)
 ├─ Warn-IfNotAdmin "no se está ejecutando como Administrador; …"
 └─ bucle while ($true):
     Clear-ScreenSafe → Show-Menu → Read-UserInput 'Seleccione una opción'
       ├─ $null (EOF en stdin) → salto de línea y break
       ├─ '1'..'5' → Invoke-OptionUsers | Invoke-OptionFilesystems | Invoke-OptionLargestFiles | Invoke-OptionMemory | Invoke-OptionBackup
       ├─ '0'      → "Hasta luego." y return
       └─ otro     → ERROR: opción no válida: '…'. Ingrese un número entre 0 y 5.
     Wait-Pause
```

La última parte del script es:

```powershell
if ($MyInvocation.InvocationName -ne '.') {
    Start-SysAdminTool
}
```

Si otro script carga el archivo mediante `. .\powershell\sysadmin-tool.ps1`
(*dot-sourcing*), solo se importan las funciones sin iniciar el menú.

## 5. Convenciones y decisiones de diseño en PowerShell

- **`Set-StrictMode -Version Latest` y `$ErrorActionPreference = 'Stop'`:**
  evita el uso de variables no inicializadas o propiedades inexistentes y
  convierte errores silenciosos en excepciones capturables con `try / catch`.
- **Separación del flujo de retorno y salida por consola:** en PowerShell,
  `Write-Output` envía objetos al *pipeline* de retorno de la función. Por eso,
  en funciones que devuelven un valor (`Select-BackupDestination`,
  `Confirm-Action`, `Test-FreeSpace`), los mensajes al usuario se escriben con
  `[Console]::Out.WriteLine(...)` para no contaminar el valor retornado.
- **Errores y advertencias por `stderr`:** `Write-ErrorMsg` y
  `Write-WarningMsg` usan `[Console]::Error.WriteLine(...)` en lugar de
  `Write-Error` de PowerShell para producir mensajes limpios de una sola línea
  (`ERROR: …`, `ADVERTENCIA: …`) idénticos a los de la herramienta en Bash.
- **Formato independiente de la configuración regional (`InvariantCulture`):**
  `Format-HumanSize` y `Format-Percentage` usan
  `[System.Globalization.CultureInfo]::InvariantCulture` para garantizar el
  punto decimal (`14.87 %`, `74.2KiB`) aunque Windows esté configurado en
  español (donde el separador por defecto es la coma).
- **Codificación UTF-8 con BOM y CRLF:** Windows PowerShell 5.1 interpreta los
  scripts `.ps1` sin BOM como Windows-1252 (rompiendo tildes y `¿`). Guardar el
  archivo en UTF-8 con BOM y configurar `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`
  garantiza que tanto PowerShell 5.1 como PowerShell 7+ muestren todos los
  caracteres correctamente.
