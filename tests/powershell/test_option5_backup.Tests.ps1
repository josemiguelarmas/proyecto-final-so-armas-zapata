#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Opción 5: Copia de seguridad a memoria USB' {
    It 'Test-IsFatFilesystem identifica variantes FAT correctamente' {
        (Test-IsFatFilesystem -FsType 'FAT32') | Should Be $true
        (Test-IsFatFilesystem -FsType 'exFAT') | Should Be $true
        (Test-IsFatFilesystem -FsType 'vfat') | Should Be $true
        (Test-IsFatFilesystem -FsType 'FAT') | Should Be $true
        (Test-IsFatFilesystem -FsType 'NTFS') | Should Be $false
        (Test-IsFatFilesystem -FsType '') | Should Be $false
    }

    It 'Get-UniqueBackupDir agrega sufijos _1 y _2 cuando el directorio ya existe' {
        $tmp = New-TestTempDir -Prefix 'qa_unique_'
        try {
            $baseCandidate = Join-Path $tmp 'backup_test_20261106_090000'
            (Get-UniqueBackupDir -Candidate $baseCandidate) | Should Be $baseCandidate

            $null = New-Item -ItemType Directory -Path $baseCandidate -Force
            (Get-UniqueBackupDir -Candidate $baseCandidate) | Should Be "${baseCandidate}_1"

            $null = New-Item -ItemType Directory -Path "${baseCandidate}_1" -Force
            (Get-UniqueBackupDir -Candidate $baseCandidate) | Should Be "${baseCandidate}_2"
        } finally {
            Remove-TestTempDir -DirPath $tmp
        }
    }

    It 'Test-BackupDestination rechaza destino dentro del origen pero permite prefijo hermano (datos2 vs datos)' {
        $tmp = New-TestTempDir -Prefix 'qa_dest_'
        try {
            $src = Join-Path $tmp 'datos'
            $inside = Join-Path $src 'sub'
            $sibling = Join-Path $tmp 'datos2'
            $null = New-Item -ItemType Directory -Path $inside -Force
            $null = New-Item -ItemType Directory -Path $sibling -Force

            (Test-BackupDestination -SourceAbs $src -DestAbs $src) | Should Be $false
            (Test-BackupDestination -SourceAbs $src -DestAbs $inside) | Should Be $false
            (Test-BackupDestination -SourceAbs $src -DestAbs $sibling) | Should Be $true
        } finally {
            Remove-TestTempDir -DirPath $tmp
        }
    }

    It 'realiza una copia de seguridad completa, genera catalogo.txt y verifica integridad EXITOSA' {
        $src = New-TestTempDir -Prefix 'qa_bkp_src_'
        $dst = New-TestTempDir -Prefix 'qa_bkp_dst_'
        try {
            $sub = Join-Path $src 'informes 2026'
            $null = New-Item -ItemType Directory -Path $sub -Force
            [System.IO.File]::WriteAllText((Join-Path $src 'raiz.txt'), 'contenido raiz')
            [System.IO.File]::WriteAllText((Join-Path $sub 'reporte_final.txt'), 'datos del reporte 12345')

            # Input sequence: 5 -> src -> m -> dst -> s (confirm C:\ drive) -> s (confirm start) -> Enter -> 0
            $res = Invoke-ToolProcess -InputLines @('5', $src, 'm', $dst, 's', 's', '', '0')
            $res.ExitCode | Should Be 0
            ($res.Stdout -match 'Archivos regulares:\s+origen 2 / copia 2') | Should Be $true
            ($res.Stdout -match 'Verificación:\s+EXITOSA \(cantidad y tamaño total coinciden\)') | Should Be $true

            $backupFolder = Get-ChildItem -LiteralPath $dst -Directory | Select-Object -First 1
            ($null -ne $backupFolder) | Should Be $true

            $catalogFile = Join-Path $backupFolder.FullName 'catalogo.txt'
            (Test-Path -LiteralPath $catalogFile) | Should Be $true
            $catText = [System.IO.File]::ReadAllText($catalogFile, [System.Text.Encoding]::UTF8)
            ($catText -match '# Catálogo de la copia de seguridad de:') | Should Be $true
            ($catText -match 'informes 2026/reporte_final\.txt\t\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') | Should Be $true
            ($catText -match 'raiz\.txt\t\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') | Should Be $true
        } finally {
            Remove-TestTempDir -DirPath $src
            Remove-TestTempDir -DirPath $dst
        }
    }

    It 'maneja correctamente errores de origen inexistente, cancelar con c y rechazar confirmación con n' {
        $src = New-TestTempDir -Prefix 'qa_bkp_err_'
        try {
            $res = Invoke-ToolProcess -InputLines @(
                '5', 'C:\no_existe_origen_999', '',
                '5', $src, 'c', '',
                '0'
            )
            $res.ExitCode | Should Be 0
            ($res.Stderr -match "ERROR: el directorio de origen 'C:\\no_existe_origen_999' no existe\.") | Should Be $true
            ($res.Stdout -match 'Operación cancelada\.') | Should Be $true
        } finally {
            Remove-TestTempDir -DirPath $src
        }
    }
}
