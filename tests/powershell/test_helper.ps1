#Requires -Version 5.1
<#
.SYNOPSIS
    test_helper.ps1 - Shared helper functions for the PowerShell Pester test suite.
#>

$script:TESTS_DIR = $PSScriptRoot
$script:REPO_ROOT = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:TOOL_PATH = Join-Path $script:REPO_ROOT 'powershell\sysadmin-tool.ps1'

# Load tool functions into the current scope without running Start-SysAdminTool
. $script:TOOL_PATH

function Invoke-ToolProcess {
    <#
    .SYNOPSIS
        Runs powershell/sysadmin-tool.ps1 in a child PowerShell process, feeding
        the provided input lines to stdin and capturing stdout, stderr and exit code.
    #>
    param(
        [string[]]$InputLines = @()
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:TOOL_PATH`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()

    if ($InputLines.Count -gt 0) {
        $payload = ($InputLines -join "`r`n") + "`r`n"
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $proc.StandardInput.BaseStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
    }
    $proc.StandardInput.Close()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $proc.ExitCode
        Stdout   = $stdout
        Stderr   = $stderr
        Combined = ($stdout + "`n" + $stderr)
    }
}

function New-TestTempDir {
    param([string]$Prefix = 'qa_ps_')
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("{0}{1}" -f $Prefix, [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $dir -Force
    return (Get-Item -LiteralPath $dir).FullName
}

function Remove-TestTempDir {
    param([string]$DirPath)
    if (-not [string]::IsNullOrEmpty($DirPath) -and (Test-Path -LiteralPath $DirPath)) {
        Remove-Item -LiteralPath $DirPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
