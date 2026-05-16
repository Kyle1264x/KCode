[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$errors = New-Object System.Collections.Generic.List[string]

function Add-SetupError {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:errors.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Add-SetupOk {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host " OK : $Message" -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($config.QueueRoot)) {
    Add-SetupError 'QueueRoot is empty.'
} elseif (Test-Path -LiteralPath $config.QueueRoot -PathType Container) {
    Add-SetupOk "QueueRoot exists: $($config.QueueRoot)"
} else {
    Add-SetupError "QueueRoot does not exist: $($config.QueueRoot)"
}

$printer = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -eq $config.DefaultPrinter } | Select-Object -First 1
if ($null -eq $printer) {
    Add-SetupError "Printer was not found in Windows: $($config.DefaultPrinter)"
} else {
    Add-SetupOk "Printer is installed: $($config.DefaultPrinter)"
}

foreach ($property in $config.SupportedExtensions.PSObject.Properties) {
    $extension = $property.Name
    $command = [Environment]::ExpandEnvironmentVariables([string]$property.Value.Command)
    if ((Get-Command -Name $command -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $command -PathType Leaf)) {
        Add-SetupOk "Command for $extension exists: $command"
    } else {
        Add-SetupError "Command for $extension does not exist: $command"
    }
}

if ($errors.Count -gt 0) {
    throw "Email print setup check failed with $($errors.Count) problem(s)."
}

Write-Host 'Email print setup check passed.' -ForegroundColor Green
