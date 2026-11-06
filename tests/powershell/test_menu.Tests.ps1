#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Menú principal y flujo de entrada/salida' {
    It 'muestra las opciones 0-5 y sale con código 0 al ingresar 0' {
        $res = Invoke-ToolProcess -InputLines @('0')
        $res.ExitCode | Should Be 0
        ($res.Stdout -match '1\) Usuarios y último inicio de sesión') | Should Be $true
        ($res.Stdout -match '2\) Sistemas de archivos y discos') | Should Be $true
        ($res.Stdout -match '3\) Los diez archivos más grandes') | Should Be $true
        ($res.Stdout -match '4\) Memoria RAM y swap') | Should Be $true
        ($res.Stdout -match '5\) Copia de seguridad a USB') | Should Be $true
        ($res.Stdout -match '0\) Salir') | Should Be $true
        ($res.Stdout -match 'Hasta luego\.') | Should Be $true
    }

    It 'EOF inmediato en stdin termina el ciclo limpiamente con código 0' {
        $res = Invoke-ToolProcess -InputLines @()
        $res.ExitCode | Should Be 0
        $matchesCount = ([regex]::Matches($res.Stdout, '0\) Salir')).Count
        $matchesCount | Should Be 1
    }

    It 'letras producen error en español por stderr y el menú continúa' {
        $res = Invoke-ToolProcess -InputLines @('abc', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stderr -match "ERROR: opción no válida: 'abc'\. Ingrese un número entre 0 y 5\.") | Should Be $true
        ($res.Stdout -match 'Hasta luego\.') | Should Be $true
    }

    It 'números fuera de rango (9, -1, 00, 10) producen error por stderr' {
        $res = Invoke-ToolProcess -InputLines @('9', '', '-1', '', '00', '', '10', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stderr -match "opción no válida: '9'") | Should Be $true
        ($res.Stderr -match "opción no válida: '-1'") | Should Be $true
        ($res.Stderr -match "opción no válida: '00'") | Should Be $true
        ($res.Stderr -match "opción no válida: '10'") | Should Be $true
        ($res.Stdout -notmatch 'opción no válida') | Should Be $true
    }

    It 'Test-Dependencies devuelve true en un entorno Windows estándar' {
        Test-Dependencies | Should Be $true
    }
}
