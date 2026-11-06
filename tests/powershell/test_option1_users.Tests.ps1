#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Opción 1: Usuarios y último inicio de sesión' {
    It 'Get-AccountRid extrae correctamente el RID final de un SID' {
        (Get-AccountRid -SidString 'S-1-5-21-2944507230-4046107389-3137548052-500') | Should Be 500
        (Get-AccountRid -SidString 'S-1-5-21-2944507230-4046107389-3137548052-1032') | Should Be 1032
        (Get-AccountRid -SidString 'SID_INVALIDO') | Should Be -1
    }

    It 'Test-IsHumanAccount clasifica correctamente Administrador (500), humanos (>=1000) y cuentas de sistema' {
        (Test-IsHumanAccount -Rid 500 -Enabled $false) | Should Be $true
        (Test-IsHumanAccount -Rid 500 -Enabled $true) | Should Be $true
        (Test-IsHumanAccount -Rid 1000 -Enabled $true) | Should Be $true
        (Test-IsHumanAccount -Rid 1032 -Enabled $true) | Should Be $true
        (Test-IsHumanAccount -Rid 501 -Enabled $false) | Should Be $false
        (Test-IsHumanAccount -Rid 503 -Enabled $false) | Should Be $false
        (Test-IsHumanAccount -Rid 504 -Enabled $false) | Should Be $false
        (Test-IsHumanAccount -Rid 1005 -Enabled $false) | Should Be $false
    }

    It 'Write-UsersTable formatea correctamente fechas, NEVER y UNAVAILABLE' {
        $fakeUsers = @(
            [PSCustomObject]@{ Name = 'admin_test'; Rid = 500; Enabled = $true; LastLogin = '2026-11-05 10:30:00' },
            [PSCustomObject]@{ Name = 'nuevo_user'; Rid = 1001; Enabled = $true; LastLogin = 'NEVER' },
            [PSCustomObject]@{ Name = 'sin_datos'; Rid = 1002; Enabled = $true; LastLogin = 'UNAVAILABLE' }
        )
        $out = (Write-UsersTable -Title 'USUARIOS DE PRUEBA' -Users $fakeUsers) -join "`n"
        ($out -match 'USUARIOS DE PRUEBA \(3\)') | Should Be $true
        ($out -match 'admin_test\s+500\s+2026-11-05\s+10:30:00') | Should Be $true
        ($out -match 'nuevo_user\s+1001\s+Nunca ha iniciado sesión') | Should Be $true
        ($out -match 'sin_datos\s+1002\s+No disponible') | Should Be $true
    }

    It 'submenú 1 muestra solo usuarios humanos y no muestra cuentas de sistema' {
        $res = Invoke-ToolProcess -InputLines @('1', '1', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stdout -match 'USUARIOS HUMANOS \(\d+\)') | Should Be $true
        ($res.Stdout -notmatch 'CUENTAS DE SISTEMA / INTEGRADAS') | Should Be $true
    }

    It 'submenú 2 muestra tanto usuarios humanos como cuentas de sistema' {
        $res = Invoke-ToolProcess -InputLines @('1', '2', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stdout -match 'USUARIOS HUMANOS \(\d+\)') | Should Be $true
        ($res.Stdout -match 'CUENTAS DE SISTEMA / INTEGRADAS \(\d+\)') | Should Be $true
    }

    It 'opción inválida en el submenú de usuarios reporta error por stderr' {
        $res = Invoke-ToolProcess -InputLines @('1', '9', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stderr -match "ERROR: opción no válida: '9'\.") | Should Be $true
    }
}
