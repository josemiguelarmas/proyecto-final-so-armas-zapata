# Pruebas de `powershell/sysadmin-tool.ps1`

Suite automatizada con **Pester** (incluido por defecto en Windows 10/11 con
Windows PowerShell 5.1 y compatible con PowerShell 7+) para la herramienta de
administración en PowerShell.

## Requisitos

- Windows 10 / 11 o Windows Server 2016+ con Windows PowerShell 5.1+.
- Módulo `Pester` (preinstalado en Windows).

## Cómo ejecutar

Desde una terminal de PowerShell en la raíz del repositorio:

```powershell
# Ejecutar toda la suite de pruebas de PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\powershell\run-tests.ps1

# Ejecutar solo un archivo de pruebas específico
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\powershell\run-tests.ps1 -TestFile test_menu.Tests.ps1
```

## Archivos de la suite (`tests/powershell/`)

| Archivo | Qué cubre |
|---|---|
| `run-tests.ps1` | Lanzador: importa Pester, ejecuta todos los archivos `*.Tests.ps1` (o los indicados por `-TestFile`) y devuelve código de salida `0` si todas pasan o `1` si alguna falla. |
| `test_helper.ps1` | Funciones compartidas: carga `powershell/sysadmin-tool.ps1` mediante *dot-sourcing*, define `Invoke-ToolProcess` (ejecuta la herramienta en un subproceso con `stdin`, `stdout` y `stderr` redirigidos en UTF-8) y `New-TestTempDir` / `Remove-TestTempDir`. |
| `test_static.Tests.ps1` | Validación sintáctica AST (`[System.Management.Automation.Language.Parser]::ParseFile`) del script principal y de los archivos de prueba; verificación de `#Requires -Version 5.1`, BOM UTF-8 (`0xEF 0xBB 0xBF`) y carga con *dot-sourcing* sin iniciar el menú. |
| `test_menu.Tests.ps1` | Menú principal: visualización de opciones `0-5`, salida limpia con `0` y con EOF inmediato en `stdin`, rechazo de entradas inválidas (`abc`, `9`, `-1`, `00`, `10`) por `stderr` sin contaminar `stdout`, y `Test-Dependencies`. |
| `test_option1_users.Tests.ps1` | `Get-AccountRid`, `Test-IsHumanAccount` (`RID 500`, `RID >= 1000`, cuentas integradas `501`/`503`/`504`), formato de `Write-UsersTable` (`NEVER`, `UNAVAILABLE`, fechas), y pruebas de integración para submenús `1`, `2` y opción inválida. |
| `test_option2_filesystems.Tests.ps1` | `Get-MaxLength`, `Get-DriveTypeName`, listado de volúmenes en bytes exactos contrastado contra `Win32_LogicalDisk` (`C:`), tabla de discos físicos (`Win32_DiskDrive`) y opción `s` para incluir todas las unidades. |
| `test_option3_largest.Tests.ps1` | `Format-HumanSize`, `Resolve-SearchPath` (`C` / `C:` → `C:\`), errores en rutas/unidades inexistentes o archivos regulares, top 10 ordenado de mayor a menor sobre un árbol temporal con 12 archivos y manejo de directorios vacíos. |
| `test_option4_memory.Tests.ps1` | `Format-Percentage` (incluyendo protección contra división por cero), `Write-MemoryLine`, y prueba de integración verificando que `TotalVisibleMemorySize * 1024` coincide en bytes exactos y que los porcentajes tienen dos decimales. |
| `test_option5_backup.Tests.ps1` | `Test-IsFatFilesystem`, `Get-UniqueBackupDir` (`_1`, `_2`), `Test-BackupDestination` (rechazo de destino dentro del origen y aceptación de prefijo hermano `datos2` vs `datos`), respaldo real completo con generación y verificación de `catalogo.txt`, y manejo de cancelación y errores. |
