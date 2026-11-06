#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Pruebas estáticas de sysadmin-tool.ps1' {
    It 'el parser AST de PowerShell no reporta errores de sintaxis en sysadmin-tool.ps1' {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:TOOL_PATH, [ref]$tokens, [ref]$errors)
        $errors.Count | Should Be 0
    }

    It 'todos los scripts de la suite de pruebas tienen sintaxis válida' {
        $files = Get-ChildItem -Path $script:TESTS_DIR -Filter '*.ps1'
        foreach ($f in $files) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
            $errors.Count | Should Be 0
        }
    }

    It 'incluye la directiva #Requires -Version 5.1 en la primera línea' {
        $firstLine = (Get-Content -LiteralPath $script:TOOL_PATH -TotalCount 1).Trim()
        $firstLine | Should Be '#Requires -Version 5.1'
    }

    It 'está codificado en UTF-8 con BOM para compatibilidad con Windows PowerShell 5.1' {
        $bytes = [System.IO.File]::ReadAllBytes($script:TOOL_PATH)
        ($bytes.Length -ge 3) | Should Be $true
        $bytes[0] | Should Be 0xEF
        $bytes[1] | Should Be 0xBB
        $bytes[2] | Should Be 0xBF
    }

    It 'al cargarse con dot-sourcing define las funciones principales sin ejecutar el menú' {
        (Get-Command -Name 'Start-SysAdminTool' -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        (Get-Command -Name 'Invoke-OptionUsers' -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        (Get-Command -Name 'Invoke-OptionFilesystems' -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        (Get-Command -Name 'Invoke-OptionLargestFiles' -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        (Get-Command -Name 'Invoke-OptionMemory' -ErrorAction SilentlyContinue) -ne $null | Should Be $true
        (Get-Command -Name 'Invoke-OptionBackup' -ErrorAction SilentlyContinue) -ne $null | Should Be $true
    }

    It 'run-tests.ps1 existe en tests/powershell/' {
        Test-Path -LiteralPath (Join-Path $script:TESTS_DIR 'run-tests.ps1') | Should Be $true
    }
}
