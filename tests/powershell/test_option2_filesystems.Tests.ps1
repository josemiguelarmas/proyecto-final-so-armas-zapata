#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Opción 2: Sistemas de archivos y discos' {
    It 'Get-MaxLength calcula la longitud de la cadena más larga' {
        (Get-MaxLength -Items @('A', 'DISPOSITIVO', 'C:')) | Should Be 11
        (Get-MaxLength -Items @('')) | Should Be 0
    }

    It 'Get-DriveTypeName traduce los tipos de unidad de Windows correctamente' {
        (Get-DriveTypeName -DriveType 2) | Should Be 'Removible'
        (Get-DriveTypeName -DriveType 3) | Should Be 'Fijo'
        (Get-DriveTypeName -DriveType 4) | Should Be 'Red'
        (Get-DriveTypeName -DriveType 5) | Should Be 'Óptico'
        (Get-DriveTypeName -DriveType 6) | Should Be 'RAMDisk'
        (Get-DriveTypeName -DriveType 99) | Should Be 'Otro'
    }

    It 'lista los sistemas de archivos montados con tamaño total y disponible en bytes exactos' {
        $cDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = 'C:'"
        $res = Invoke-ToolProcess -InputLines @('2', 'N', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stdout -match 'DISPOSITIVO\s+TIPO\s+TOTAL \(BYTES\)\s+DISPONIBLE \(BYTES\)\s+MONTAJE \(ETIQUETA\)') | Should Be $true
        ($res.Stdout -match ("C:\s+NTFS\s+{0}\s+\d+" -f $cDrive.Size)) | Should Be $true
        ($res.Stdout -match 'Discos físicos \(Win32_DiskDrive\):') | Should Be $true
    }

    It 'acepta s para incluir todas las unidades conectadas' {
        $res = Invoke-ToolProcess -InputLines @('2', 's', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stdout -match 'C:\s+NTFS') | Should Be $true
    }
}
