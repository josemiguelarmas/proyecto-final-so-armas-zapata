#Requires -Version 5.1
<#
.SYNOPSIS
    sysadmin-tool.ps1 - Interactive system administration tool for data center
    administrators. Final project, Operating Systems course, Universidad Icesi.

.DESCRIPTION
    Provides an interactive menu with five system administration options:
      1) System users and last login date/time
      2) Connected filesystems and disks (total size and free space in bytes)
      3) Ten largest files on a specified disk or filesystem
      4) Free RAM and swap (page file) in use (in bytes and percentage)
      5) Directory backup to a USB drive with modification catalog

    All user-facing text is in Spanish; code and comments are in English.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure UTF-8 console output so Spanish accents render properly in all terminals.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Ignore if running in a host without a console handle.
}

$script:SCRIPT_NAME = $MyInvocation.MyCommand.Name
if ([string]::IsNullOrEmpty($script:SCRIPT_NAME)) {
    $script:SCRIPT_NAME = 'sysadmin-tool.ps1'
}

# In Windows, built-in Administrator has RID 500 and user-created accounts
# start at RID 1000 (analogous to UID 0 and UID >= 1000 in Linux).
$script:ADMIN_RID = 500
$script:HUMAN_RID_MIN = 1000

# DriveType values from Win32_LogicalDisk / Win32_Volume:
# 2 = Removable disk, 3 = Local fixed disk, 4 = Network drive, 5 = Compact Disc, 6 = RAM disk
$script:FIXED_DRIVE_TYPES = @(2, 3)

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

function Write-ErrorMsg {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine("ERROR: $Message")
}

function Write-WarningMsg {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine("ADVERTENCIA: $Message")
}

function Write-Header {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Output ""
    Write-Output "=== $Title ==="
    Write-Output ""
}

function Write-Field {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $pad = [Math]::Max(1, 22 - $Label.Length)
    Write-Output ("  {0}{1} {2}" -f $Label, (' ' * $pad), $Value)
}

function Clear-ScreenSafe {
    try {
        if (-not [Console]::IsOutputRedirected) {
            Clear-Host
        }
    } catch {
        # Output is redirected or host does not support clearing.
    }
}

function Wait-Pause {
    Write-Output ""
    $null = Read-UserInput -Prompt 'Presione Enter para volver al menú...'
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Warn-IfNotAdmin {
    param([Parameter(Mandatory = $true)][string]$Message)
    if (-not (Test-IsAdmin)) {
        Write-WarningMsg $Message
    }
}

function Read-UserInput {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    try {
        if ([Console]::IsInputRedirected) {
            $line = [Console]::In.ReadLine()
            return $line
        } else {
            return (Read-Host -Prompt $Prompt)
        }
    } catch {
        return $null
    }
}

function Read-UserPath {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    $raw = Read-UserInput -Prompt $Prompt
    if ($null -eq $raw) {
        return $null
    }
    if ($raw -eq '~') {
        return $HOME
    }
    if ($raw.StartsWith('~\') -or $raw.StartsWith('~/')) {
        return (Join-Path -Path $HOME -ChildPath $raw.Substring(2))
    }
    return $raw
}

function Confirm-Action {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    $answer = Read-UserInput -Prompt $Prompt
    if ($null -ne $answer -and $answer -match '^[sS]$') {
        return $true
    }
    Write-Output 'Operación cancelada.'
    return $false
}

function Format-HumanSize {
    param([Parameter(Mandatory = $true)][int64]$Bytes)
    if ($Bytes -lt 1024) {
        return "{0}B" -f $Bytes
    }
    $units = @('B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB')
    $val = [double]$Bytes
    $idx = 0
    while ($val -ge 1024.0 -and $idx -lt ($units.Count - 1)) {
        $val /= 1024.0
        $idx++
    }
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F1}{1}", $val, $units[$idx]))
}

function Format-Percentage {
    param(
        [Parameter(Mandatory = $true)][int64]$Part,
        [Parameter(Mandatory = $true)][int64]$Total
    )
    if ($Total -le 0) {
        return '0.00'
    }
    $pct = ([double]$Part * 100.0) / [double]$Total
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", $pct))
}

function Get-MaxLength {
    param([Parameter(Mandatory = $true)][string[]]$Items)
    $max = 0
    foreach ($item in $Items) {
        if ($null -ne $item -and $item.Length -gt $max) {
            $max = $item.Length
        }
    }
    return $max
}

# ---------------------------------------------------------------------------
# Startup checks
# ---------------------------------------------------------------------------

function Test-Dependencies {
    $requiredCmds = @('Get-CimInstance', 'Get-ChildItem', 'Copy-Item', 'Get-FileHash')
    $missing = @()
    foreach ($cmd in $requiredCmds) {
        if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
            $missing += $cmd
        }
    }
    if ($missing.Count -gt 0) {
        Write-ErrorMsg ("{0}: faltan cmdlets obligatorios: {1}" -f $script:SCRIPT_NAME, ($missing -join ', '))
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Option 1: users and last login
# ---------------------------------------------------------------------------

function Get-AccountRid {
    param([Parameter(Mandatory = $true)][string]$SidString)
    if ($SidString -match '-(\d+)$') {
        return [int]$Matches[1]
    }
    return -1
}

function Test-IsHumanAccount {
    param(
        [Parameter(Mandatory = $true)][int]$Rid,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )
    # Built-in Administrator (RID 500) and regular user accounts (RID >= 1000)
    return ($Rid -eq $script:ADMIN_RID -or ($Rid -ge $script:HUMAN_RID_MIN -and $Enabled))
}

function Get-LocalUserRecords {
    # Primary source: Get-LocalUser (Microsoft.PowerShell.LocalAccounts).
    # Fallback: Win32_UserAccount + Win32_NetworkLoginProfile via CIM.
    $records = @()
    if (Get-Command -Name 'Get-LocalUser' -ErrorAction SilentlyContinue) {
        $script:LOGIN_SOURCE = 'Get-LocalUser (SAM local)'
        $users = Get-LocalUser -ErrorAction Stop
        foreach ($u in $users) {
            $rid = Get-AccountRid -SidString $u.SID.Value
            $lastLoginStr = 'NEVER'
            if ($null -ne $u.LastLogon -and $u.LastLogon.Year -gt 1970) {
                $lastLoginStr = $u.LastLogon.ToString('yyyy-MM-dd HH:mm:ss')
            }
            $records += [PSCustomObject]@{
                Name      = $u.Name
                Rid       = $rid
                Enabled   = [bool]$u.Enabled
                LastLogin = $lastLoginStr
            }
        }
    } else {
        $script:LOGIN_SOURCE = 'Win32_UserAccount / Win32_NetworkLoginProfile (CIM)'
        $cimUsers = Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = True' -ErrorAction Stop
        $profiles = @{}
        try {
            foreach ($p in (Get-CimInstance -ClassName Win32_NetworkLoginProfile -ErrorAction SilentlyContinue)) {
                if ($null -ne $p.Name -and $null -ne $p.LastLogon) {
                    $profiles[$p.Name.Split('\')[-1].ToLowerInvariant()] = $p.LastLogon
                }
            }
        } catch {
            # Ignore if profile query fails.
        }
        foreach ($u in $cimUsers) {
            $rid = Get-AccountRid -SidString $u.SID
            $lastLoginStr = 'NEVER'
            $key = $u.Name.ToLowerInvariant()
            if ($profiles.ContainsKey($key)) {
                $dt = $profiles[$key]
                if ($dt -is [DateTime] -and $dt.Year -gt 1970) {
                    $lastLoginStr = $dt.ToString('yyyy-MM-dd HH:mm:ss')
                }
            }
            $records += [PSCustomObject]@{
                Name      = $u.Name
                Rid       = $rid
                Enabled   = (-not [bool]$u.Disabled)
                LastLogin = $lastLoginStr
            }
        }
    }
    return $records
}

function Write-UsersTable {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowEmptyCollection()][object[]]$Users
    )
    Write-Output ("{0} ({1})" -f $Title, $Users.Count)
    Write-Output ("{0,-24} {1,8}  {2,-10} {3,-8}" -f 'USUARIO', 'RID', 'FECHA', 'HORA')
    Write-Output ("{0,-24} {1,8}  {2,-10} {3,-8}" -f '-------', '---', '-----', '----')
    foreach ($u in $Users) {
        if ($u.LastLogin -eq 'NEVER') {
            Write-Output ("{0,-24} {1,8}  {2}" -f $u.Name, $u.Rid, 'Nunca ha iniciado sesión')
        } elseif ($u.LastLogin -eq 'UNAVAILABLE') {
            Write-Output ("{0,-24} {1,8}  {2}" -f $u.Name, $u.Rid, 'No disponible')
        } else {
            $parts = $u.LastLogin -split ' ', 2
            Write-Output ("{0,-24} {1,8}  {2,-10} {3,-8}" -f $u.Name, $u.Rid, $parts[0], $parts[1])
        }
    }
    Write-Output ""
}

function Invoke-OptionUsers {
    Write-Header 'Usuarios del sistema y último inicio de sesión'
    Write-Output ("  1) Solo usuarios humanos (Administrador RID {0} y cuentas activas RID >= {1})" -f $script:ADMIN_RID, $script:HUMAN_RID_MIN)
    Write-Output '  2) Todas las cuentas locales (humanas, integradas y de sistema)'
    $choice = Read-UserInput -Prompt 'Seleccione'
    if ($null -eq $choice) {
        return
    }
    if ($choice -ne '1' -and $choice -ne '2') {
        Write-ErrorMsg ("opción no válida: '{0}'." -f $choice)
        return
    }

    try {
        $records = @(Get-LocalUserRecords)
    } catch {
        Write-ErrorMsg ("no se pudo obtener la lista de usuarios: {0}" -f $_.Exception.Message)
        return
    }

    Write-Output ""
    Write-Output ("Fuente del último inicio de sesión: {0}" -f $script:LOGIN_SOURCE)
    Write-Output ""

    $humans = @()
    $system = @()
    foreach ($r in $records) {
        if (Test-IsHumanAccount -Rid $r.Rid -Enabled $r.Enabled) {
            $humans += $r
        } else {
            $system += $r
        }
    }

    Write-UsersTable -Title 'USUARIOS HUMANOS' -Users $humans
    if ($choice -eq '2') {
        Write-UsersTable -Title 'CUENTAS DE SISTEMA / INTEGRADAS' -Users $system
    }
}

# ---------------------------------------------------------------------------
# Option 2: filesystems and disks
# ---------------------------------------------------------------------------

function Get-DriveTypeName {
    param([int]$DriveType)
    switch ($DriveType) {
        2 { return 'Removible' }
        3 { return 'Fijo' }
        4 { return 'Red' }
        5 { return 'Óptico' }
        6 { return 'RAMDisk' }
        default { return 'Otro' }
    }
}

function Invoke-OptionFilesystems {
    Write-Header 'Sistemas de archivos y discos'
    $choice = Read-UserInput -Prompt '¿Incluir unidades de red, ópticas o sin formato? [s/N]'
    if ($null -eq $choice) {
        return
    }
    $includeAll = ($choice -match '^[sS]$')

    try {
        $logicalDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop)
    } catch {
        Write-ErrorMsg ("no se pudo consultar Win32_LogicalDisk: {0}" -f $_.Exception.Message)
        return
    }

    $rows = @()
    foreach ($d in $logicalDisks) {
        if (-not $includeAll -and ($script:FIXED_DRIVE_TYPES -notcontains [int]$d.DriveType)) {
            continue
        }
        if (-not $includeAll -and $null -eq $d.Size) {
            continue
        }
        $fsType = if ([string]::IsNullOrEmpty($d.FileSystem)) { 'RAW/N/A' } else { [string]$d.FileSystem }
        $sizeStr = if ($null -ne $d.Size) { [string]$d.Size } else { '0' }
        $freeStr = if ($null -ne $d.FreeSpace) { [string]$d.FreeSpace } else { '0' }
        $label = if ([string]::IsNullOrEmpty($d.VolumeName)) { '-' } else { [string]$d.VolumeName }
        $mount = "{0}\ ({1})" -f $d.DeviceID, $label

        $rows += [PSCustomObject]@{
            Source = [string]$d.DeviceID
            Type   = $fsType
            Size   = $sizeStr
            Avail  = $freeStr
            Target = $mount
        }
    }

    if ($rows.Count -eq 0) {
        Write-ErrorMsg 'no se encontró ningún sistema de archivos montado.'
        return
    }

    $wSrc = Get-MaxLength -Items (@('DISPOSITIVO') + @($rows | ForEach-Object { $_.Source }))
    $wType = Get-MaxLength -Items (@('TIPO') + @($rows | ForEach-Object { $_.Type }))
    $wTarget = Get-MaxLength -Items (@('MONTAJE (ETIQUETA)') + @($rows | ForEach-Object { $_.Target }))

    $headerFmt = "{0,-$wSrc}  {1,-$wType}  {2,18}  {3,18}  {4}"
    Write-Output ($headerFmt -f 'DISPOSITIVO', 'TIPO', 'TOTAL (BYTES)', 'DISPONIBLE (BYTES)', 'MONTAJE (ETIQUETA)')
    Write-Output ('-' * ($wSrc + $wType + $wTarget + 44))
    foreach ($r in $rows) {
        Write-Output ($headerFmt -f $r.Source, $r.Type, $r.Size, $r.Avail, $r.Target)
    }

    Write-Output ""
    Write-Output 'Discos físicos (Win32_DiskDrive):'
    try {
        $physDisks = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Sort-Object -Property Index)
        if ($physDisks.Count -eq 0) {
            Write-WarningMsg 'no se detectaron discos físicos.'
        } else {
            $wDev = Get-MaxLength -Items (@('DISPOSITIVO') + @($physDisks | ForEach-Object { [string]$_.DeviceID }))
            $wBus = Get-MaxLength -Items (@('BUS') + @($physDisks | ForEach-Object { [string]$_.InterfaceType }))
            $diskFmt = "{0,-$wDev}  {1,18}  {2,-$wBus}  {3}"
            Write-Output ($diskFmt -f 'DISPOSITIVO', 'TAMAÑO (BYTES)', 'BUS', 'MODELO')
            foreach ($pd in $physDisks) {
                $pSize = if ($null -ne $pd.Size) { [string]$pd.Size } else { '0' }
                $pBus = if ([string]::IsNullOrEmpty($pd.InterfaceType)) { '-' } else { [string]$pd.InterfaceType }
                $pModel = if ([string]::IsNullOrEmpty($pd.Model)) { '-' } else { [string]$pd.Model }
                Write-Output ($diskFmt -f $pd.DeviceID, $pSize, $pBus, $pModel)
            }
        }
    } catch {
        Write-WarningMsg 'no se pudo obtener la información de discos físicos (Win32_DiskDrive).'
    }
}

# ---------------------------------------------------------------------------
# Option 3: ten largest files
# ---------------------------------------------------------------------------

function Resolve-SearchPath {
    param([Parameter(Mandatory = $true)][string]$InputPath)
    $trimmed = $InputPath.Trim()
    # Normalize bare drive letters ("C" or "C:") to root path ("C:\")
    if ($trimmed -match '^[a-zA-Z]$') {
        $trimmed = "${trimmed}:\"
    } elseif ($trimmed -match '^[a-zA-Z]:$') {
        $trimmed = "${trimmed}\"
    }

    if (-not (Test-Path -LiteralPath $trimmed -ErrorAction SilentlyContinue)) {
        if ($trimmed -match '^[a-zA-Z]:\\$') {
            Write-ErrorMsg ("la unidad '{0}' no existe o no está montada." -f $trimmed.Substring(0, 2))
        } else {
            Write-ErrorMsg ("'{0}' no existe." -f $InputPath)
        }
        return $null
    }

    try {
        $item = Get-Item -LiteralPath $trimmed -Force -ErrorAction Stop
    } catch {
        Write-ErrorMsg ("no hay permiso para acceder a '{0}'." -f $InputPath)
        return $null
    }

    if (-not $item.PSIsContainer) {
        Write-ErrorMsg ("'{0}' no es un directorio ni una unidad de disco." -f $InputPath)
        return $null
    }

    # Verify we can actually list the directory root
    try {
        $null = [System.IO.Directory]::GetFileSystemEntries($item.FullName)
    } catch {
        Write-ErrorMsg ("no hay permiso para acceder a '{0}'." -f $InputPath)
        return $null
    }

    return $item.FullName
}

function Write-MemoryLine {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int64]$Bytes,
        [string]$Percent = ''
    )
    $human = Format-HumanSize -Bytes $Bytes
    if (-not [string]::IsNullOrEmpty($Percent)) {
        Write-Output ("  {0,-27} {1,16} bytes  {2,10}  {3,6} %" -f $Label, $Bytes, $human, $Percent)
    } else {
        Write-Output ("  {0,-27} {1,16} bytes  {2,10}" -f $Label, $Bytes, $human)
    }
}

function Invoke-OptionLargestFiles {
    Write-Header 'Los diez archivos más grandes'
    $inputPath = Read-UserPath -Prompt 'Ingrese una unidad (ej. C:) o directorio (ej. C:\Windows)'
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        Write-ErrorMsg 'no se ingresó ninguna ruta.'
        return
    }

    $searchPath = Resolve-SearchPath -InputPath $inputPath
    if ($null -eq $searchPath) {
        return
    }

    $rootPath = [System.IO.Path]::GetPathRoot($searchPath)
    Write-Output ""
    Write-Output ("Buscando en: {0}" -f $searchPath)
    if (-not [string]::IsNullOrEmpty($rootPath) -and ($searchPath.TrimEnd('\') -ne $rootPath.TrimEnd('\'))) {
        Write-Output ("Nota: no es la raíz de la unidad; pertenece al sistema de archivos montado en {0}." -f $rootPath)
        Write-Output 'Se busca solo dentro de esta ruta, sin cruzar enlaces simbólicos ni puntos de montaje.'
    }
    Warn-IfNotAdmin 'sin privilegios de Administrador algunos directorios pueden no ser accesibles.'
    Write-Output 'Esto puede tardar en sistemas de archivos grandes...'
    Write-Output ""

    # Iterative traversal skipping directory reparse points (analogous to find -xdev)
    # so junctions, symlinks or mounted volumes on other disks are not crossed.
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($searchPath)
    $files = New-Object System.Collections.Generic.List[object]
    $errorCount = 0

    while ($stack.Count -gt 0) {
        $currentDir = $stack.Pop()
        $dirInfo = $null
        try {
            $dirInfo = New-Object System.IO.DirectoryInfo($currentDir)
            foreach ($f in $dirInfo.EnumerateFiles()) {
                # Skip reparse point files (symlinks) to match find -type f behavior
                if (($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    $files.Add([PSCustomObject]@{
                        Length   = [int64]$f.Length
                        FullName = [string]$f.FullName
                    })
                }
            }
        } catch {
            $errorCount++
            continue
        }

        try {
            foreach ($subDir in $dirInfo.EnumerateDirectories()) {
                if (($subDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    $stack.Push($subDir.FullName)
                }
            }
        } catch {
            $errorCount++
        }
    }

    Write-Output ("{0,3}  {1,16}  {2,10}  {3}" -f '#', 'BYTES', 'LEGIBLE', 'RUTA')
    if ($files.Count -eq 0) {
        Write-Output ("No se encontraron archivos regulares en {0}." -f $searchPath)
    } else {
        $top10 = @($files | Sort-Object -Property @{Expression = 'Length'; Descending = $true }, @{Expression = 'FullName'; Ascending = $true } | Select-Object -First 10)
        $rank = 0
        foreach ($entry in $top10) {
            $rank++
            $human = Format-HumanSize -Bytes $entry.Length
            Write-Output ("{0,3}  {1,16}  {2,10}  {3}" -f $rank, $entry.Length, $human, $entry.FullName)
        }
    }

    if ($errorCount -gt 0) {
        Write-Output ""
        Write-WarningMsg ("no se pudo leer {0} ruta(s) (permisos u otros errores); los resultados pueden estar incompletos." -f $errorCount)
    }
}

# ---------------------------------------------------------------------------
# Option 4: RAM and swap
# ---------------------------------------------------------------------------

function Invoke-OptionMemory {
    Write-Header 'Memoria RAM y swap'
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    } catch {
        Write-ErrorMsg ("no se pudo consultar Win32_OperatingSystem: {0}" -f $_.Exception.Message)
        return
    }

    if ($null -eq $os.TotalVisibleMemorySize -or $os.TotalVisibleMemorySize -le 0) {
        Write-ErrorMsg 'no se pudo interpretar la información de memoria de Win32_OperatingSystem.'
        return
    }

    # Win32_OperatingSystem reports values in KiB; multiply by 1024 for exact bytes.
    [int64]$memTotal = [int64]$os.TotalVisibleMemorySize * 1024L
    [int64]$memFree  = [int64]$os.FreePhysicalMemory * 1024L
    [int64]$swapTotal = if ($null -ne $os.SizeStoredInPagingFiles) { [int64]$os.SizeStoredInPagingFiles * 1024L } else { 0L }
    [int64]$swapFree  = if ($null -ne $os.FreeSpaceInPagingFiles) { [int64]$os.FreeSpaceInPagingFiles * 1024L } else { 0L }

    Write-Output 'Memoria RAM (fuente: Win32_OperatingSystem)'
    Write-MemoryLine -Label 'Total (VisibleMemory):' -Bytes $memTotal
    Write-MemoryLine -Label 'Libre (FreePhysical):' -Bytes $memFree -Percent (Format-Percentage -Part $memFree -Total $memTotal)
    Write-Output '  (FreePhysicalMemory representa la memoria RAM física inmediatamente disponible'
    Write-Output '   sin necesidad de escribir en el archivo de paginación.)'
    Write-Output ""

    Write-Output 'Swap / Archivo de paginación'
    if ($swapTotal -le 0) {
        Write-MemoryLine -Label 'Total (PagingFiles):' -Bytes 0
        Write-Output '  No hay swap/archivo de paginación configurado; el uso es 0 bytes y el porcentaje no aplica.'
        return
    }

    [int64]$swapUsed = [Math]::Max(0L, $swapTotal - $swapFree)
    Write-MemoryLine -Label 'Total (PagingFiles):' -Bytes $swapTotal
    Write-MemoryLine -Label 'Usada (Total - Free):' -Bytes $swapUsed -Percent (Format-Percentage -Part $swapUsed -Total $swapTotal)
}

# ---------------------------------------------------------------------------
# Option 5: backup to USB (implemented in next commit)
# ---------------------------------------------------------------------------

function Invoke-OptionBackup {
    Write-Header 'Copia de seguridad a memoria USB'
    Write-WarningMsg 'Opción 5 pendiente de implementación.'
}

# ---------------------------------------------------------------------------
# Menu and entry point
# ---------------------------------------------------------------------------

function Show-Menu {
    $hostName = if (-not [string]::IsNullOrEmpty($env:COMPUTERNAME)) { $env:COMPUTERNAME } else { 'Windows' }
    Write-Output ""
    Write-Output '========================================'
    Write-Output ("  Herramienta de administración - {0}" -f $hostName)
    Write-Output '========================================'
    Write-Output '  1) Usuarios y último inicio de sesión'
    Write-Output '  2) Sistemas de archivos y discos'
    Write-Output '  3) Los diez archivos más grandes'
    Write-Output '  4) Memoria RAM y swap'
    Write-Output '  5) Copia de seguridad a USB'
    Write-Output '  0) Salir'
    Write-Output '========================================'
}

function Start-SysAdminTool {
    if (-not (Test-Dependencies)) {
        exit 1
    }
    Warn-IfNotAdmin 'no se está ejecutando como Administrador; algunas opciones pueden mostrar información incompleta.'

    while ($true) {
        Clear-ScreenSafe
        Show-Menu
        $choice = Read-UserInput -Prompt 'Seleccione una opción'
        if ($null -eq $choice) {
            Write-Output ""
            break
        }
        switch ($choice) {
            '1' { Invoke-OptionUsers }
            '2' { Invoke-OptionFilesystems }
            '3' { Invoke-OptionLargestFiles }
            '4' { Invoke-OptionMemory }
            '5' { Invoke-OptionBackup }
            '0' {
                Write-Output 'Hasta luego.'
                return
            }
            default {
                Write-ErrorMsg ("opción no válida: '{0}'. Ingrese un número entre 0 y 5." -f $choice)
            }
        }
        Wait-Pause
    }
}

# Run the menu only when executed directly; when dot-sourced (e.g. by tests),
# just load the functions.
if ($MyInvocation.InvocationName -ne '.') {
    Start-SysAdminTool
}
