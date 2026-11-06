#Requires -Version 5.1

. "$PSScriptRoot\test_helper.ps1"

Describe 'Opción 4: Memoria RAM y swap' {
    It 'Format-Percentage calcula porcentajes con dos decimales y evita división por cero' {
        (Format-Percentage -Part 0 -Total 0) | Should Be '0.00'
        (Format-Percentage -Part 50 -Total 0) | Should Be '0.00'
        (Format-Percentage -Part 1 -Total 4) | Should Be '25.00'
        (Format-Percentage -Part 1 -Total 3) | Should Be '33.33'
        (Format-Percentage -Part 100 -Total 100) | Should Be '100.00'
    }

    It 'Write-MemoryLine formatea línea con y sin porcentaje' {
        $line1 = Write-MemoryLine -Label 'Total (VisibleMemory):' -Bytes 8589934592
        ($line1 -match 'Total \(VisibleMemory\):\s+8589934592 bytes\s+8\.0GiB') | Should Be $true

        $line2 = Write-MemoryLine -Label 'Libre (FreePhysical):' -Bytes 2147483648 -Percent '25.00'
        ($line2 -match 'Libre \(FreePhysical\):\s+2147483648 bytes\s+2\.0GiB\s+25\.00 %') | Should Be $true
    }

    It 'muestra la memoria RAM libre y el swap en uso en bytes exactos (KiB * 1024) y porcentaje' {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $expectedTotalBytes = [int64]$os.TotalVisibleMemorySize * 1024L

        $res = Invoke-ToolProcess -InputLines @('4', '', '0')
        $res.ExitCode | Should Be 0
        ($res.Stdout -match 'Memoria RAM \(fuente: Win32_OperatingSystem\)') | Should Be $true
        ($res.Stdout -match ("Total \(VisibleMemory\):\s+{0} bytes" -f $expectedTotalBytes)) | Should Be $true
        ($res.Stdout -match 'Libre \(FreePhysical\):\s+\d+ bytes\s+\S+\s+\d+\.\d{2} %') | Should Be $true
        ($res.Stdout -match 'Swap / Archivo de paginación') | Should Be $true
        ($res.Stdout -match 'Total \(PagingFiles\):\s+\d+ bytes') | Should Be $true
    }
}
