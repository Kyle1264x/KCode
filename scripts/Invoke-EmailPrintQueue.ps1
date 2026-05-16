[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$incoming = Join-Path -Path $config.QueueRoot -ChildPath $config.IncomingFolder
$logRoot = Join-Path -Path $config.QueueRoot -ChildPath $config.LogFolder
$jobScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-EmailPrintJob.ps1'
$lockPath = Join-Path -Path $config.QueueRoot -ChildPath 'print-worker.lock'

New-DirectoryIfMissing -Path $config.QueueRoot
New-DirectoryIfMissing -Path $incoming
New-DirectoryIfMissing -Path $logRoot

$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $lockBytes = [System.Text.Encoding]::UTF8.GetBytes("$PID $([DateTime]::UtcNow.ToString('o'))")
    $lockStream.SetLength(0)
    $lockStream.Write($lockBytes, 0, $lockBytes.Length)

    Get-ChildItem -LiteralPath $incoming -Directory | Sort-Object Name | ForEach-Object {
        $readyPath = Join-Path -Path $_.FullName -ChildPath '.ready'
        if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
            & $jobScript -JobPath $_.FullName -ConfigPath $ConfigPath
        }
    }
} catch [System.IO.IOException] {
    Write-Host "Another email print queue worker is already running."
} finally {
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
    }
}
