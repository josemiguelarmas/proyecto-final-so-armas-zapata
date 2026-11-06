#Requires -Version 5.1
<#
.SYNOPSIS
    run-tests.ps1 - Runs the Pester automated test suite for powershell/sysadmin-tool.ps1.

.EXAMPLE
    .\tests\powershell\run-tests.ps1
    .\tests\powershell\run-tests.ps1 -TestFile test_menu.Tests.ps1
#>

param(
    [string[]]$TestFile = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsDir = $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name Pester)) {
    [Console]::Error.WriteLine('ERROR: El módulo Pester no está disponible en esta instalación de PowerShell.')
    exit 2
}

Import-Module Pester -ErrorAction Stop

$targets = @()
if ($TestFile.Count -eq 0) {
    $targets = @($testsDir)
} else {
    foreach ($f in $TestFile) {
        if (Test-Path -LiteralPath $f) {
            $targets += (Resolve-Path -LiteralPath $f).Path
        } else {
            $candidate = Join-Path $testsDir $f
            $targets += $candidate
        }
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("Ejecutando suite Pester como {0} (Administrador: {1})" -f $env:USERNAME, $isAdmin)

$result = Invoke-Pester -Script $targets -PassThru
if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
