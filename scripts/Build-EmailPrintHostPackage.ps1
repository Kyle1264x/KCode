[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [string]$PackageName = 'EmailPrintHostSetup'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path -Path $repoRoot -ChildPath 'dist'
}

$stagingRoot = Join-Path -Path $OutputDirectory -ChildPath $PackageName
$zipPath = Join-Path -Path $OutputDirectory -ChildPath ("{0}.zip" -f $PackageName)

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path -Path $stagingRoot -ChildPath 'scripts') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path -Path $stagingRoot -ChildPath 'config') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path -Path $stagingRoot -ChildPath 'docs') | Out-Null

$rootFiles = @(
    'Setup-EmailPrintHost.cmd',
    'README.md'
)
$scriptFiles = @(
    'Setup-EmailPrintHost.ps1',
    'Invoke-EmailPrintJob.ps1',
    'Invoke-EmailPrintQueue.ps1',
    'Install-EmailPrintScheduledTask.ps1',
    'Test-EmailPrintSetup.ps1'
)
$configFiles = @(
    'print-worker.example.json',
    'power-automate-flow-settings.example.json'
)
$docFiles = @(
    'power-automate-setup.md'
)

foreach ($file in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath $file) -Destination (Join-Path -Path $stagingRoot -ChildPath $file) -Force
}
foreach ($file in $scriptFiles) {
    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath "scripts\$file") -Destination (Join-Path -Path $stagingRoot -ChildPath "scripts\$file") -Force
}
foreach ($file in $configFiles) {
    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath "config\$file") -Destination (Join-Path -Path $stagingRoot -ChildPath "config\$file") -Force
}
foreach ($file in $docFiles) {
    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath "docs\$file") -Destination (Join-Path -Path $stagingRoot -ChildPath "docs\$file") -Force
}

$quickStart = @'
Email Print Host Setup
======================

1. Copy this whole folder to the Windows computer that will host printing.
2. Double-click Setup-EmailPrintHost.cmd.
3. Answer the prompts. Each prompt explains what the value is and how to find it.
4. Let setup install SumatraPDF and OneDrive if prompted.
5. Sign in to OneDrive and sync the queue folder if OneDrive was installed or opened.
6. Build the Power Automate cloud flow using docs\power-automate-setup.md.

Never save the Outlook password in this folder. Sign into abricoh@outlook.com only through Microsoft's Power Automate/Outlook connector sign-in page.
'@
Set-Content -LiteralPath (Join-Path -Path $stagingRoot -ChildPath 'START-HERE.txt') -Value $quickStart -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -LiteralPath (Join-Path -Path $stagingRoot -ChildPath '*') -DestinationPath $zipPath -Force

Write-Host "Package folder: $stagingRoot" -ForegroundColor Green
Write-Host "Package zip   : $zipPath" -ForegroundColor Green
Write-Host 'Send the zip to the print PC, extract it, then double-click Setup-EmailPrintHost.cmd.' -ForegroundColor Yellow
