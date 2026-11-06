#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Opción 3: Los diez archivos más grandes' {
    It 'Format-HumanSize formatea bytes a unidades IEC correctamente' {
        (Format-HumanSize -Bytes 0) | Should Be '0B'
        (Format-HumanSize -Bytes 1023) | Should Be '1023B'
        (Format-HumanSize -Bytes 1024) | Should Be '1.0KiB'
        (Format-HumanSize -Bytes 1572864) | Should Be '1.5MiB'
        (Format-HumanSize -Bytes 2147483648) | Should Be '2.0GiB'
    }

    It 'Resolve-SearchPath normaliza letras de unidad C y C: hacia C:\' {
        (Resolve-SearchPath -InputPath 'C') | Should Be 'C:\'
        (Resolve-SearchPath -InputPath 'C:') | Should Be 'C:\'
    }

    It 'reporta error en unidad inexistente, ruta inexistente, archivo regular o entrada vacía' {
        $res = Invoke-ToolProcess -InputLines @('3', '', '', '3', 'Z:', '', '3', 'C:\ruta_que_no_existe_12345', '', '3', $script:TOOL_PATH, '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stderr -match 'ERROR: no se ingresó ninguna ruta\.') | Should Be $true
        ($res.Stderr -match "ERROR: la unidad 'Z:' no existe o no está montada\.") | Should Be $true
        ($res.Stderr -match "ERROR: 'C:\\ruta_que_no_existe_12345' no existe\.") | Should Be $true
        ($res.Stderr -match 'no es un directorio ni una unidad de disco\.') | Should Be $true
    }

    It 'muestra como máximo los 10 archivos más grandes en orden descendente con su ruta completa' {
        $tmpDir = New-TestTempDir -Prefix 'qa_opt3_'
        try {
            $subDir = Join-Path $tmpDir 'sub carpeta con espacios'
            $null = New-Item -ItemType Directory -Path $subDir -Force
            for ($i = 1; $i -le 12; $i++) {
                $filePath = Join-Path $subDir ("archivo_{0:D2}.bin" -f $i)
                $size = $i * 100
                [System.IO.File]::WriteAllBytes($filePath, (New-Object byte[] $size))
            }

            $res = Invoke-ToolProcess -InputLines @('3', $tmpDir, '', '0')
            $res.ExitCode | Should Be 0
            ($res.Stdout -match '1\s+1200\s+1\.2KiB\s+.*archivo_12\.bin') | Should Be $true
            ($res.Stdout -match '10\s+300\s+300B\s+.*archivo_03\.bin') | Should Be $true
            ($res.Stdout -notmatch 'archivo_02\.bin') | Should Be $true
            ($res.Stdout -notmatch 'archivo_01\.bin') | Should Be $true
        } finally {
            Remove-TestTempDir -DirPath $tmpDir
        }
    }

    It 'informa cuando un directorio no contiene archivos regulares' {
        $emptyDir = New-TestTempDir -Prefix 'qa_opt3_empty_'
        try {
            $res = Invoke-ToolProcess -InputLines @('3', $emptyDir, '', '0')
            $res.ExitCode | Should Be 0
            ($res.Stdout -match 'No se encontraron archivos regulares en') | Should Be $true
        } finally {
            Remove-TestTempDir -DirPath $emptyDir
        }
    }
}
