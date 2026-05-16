[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\EmailPrint',
    [string]$QueueRoot = 'C:\EmailPrintQueue',
    [string]$DefaultPrinter = '',
    [string]$SumatraPdfPath = 'C:\Program Files\SumatraPDF\SumatraPDF.exe',
    [int]$EveryMinutes = 1,
    [switch]$NoScheduledTask,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-DefaultedInput {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if ($NonInteractive) {
        return $DefaultValue
    }

    $value = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }
    return $value.Trim()
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [bool]$DefaultYes = $true
    )

    if ($NonInteractive) {
        return $DefaultYes
    }

    if ($DefaultYes) {
        $suffix = 'Y/n'
    } else {
        $suffix = 'y/N'
    }

    while ($true) {
        $answer = Read-Host "$Prompt [$suffix]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $DefaultYes
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Host 'Please enter y or n.' -ForegroundColor Yellow }
        }
    }
}

function Select-PrinterName {
    param([string]$CurrentValue)

    if ($NonInteractive -and -not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue
    }

    $printers = @(Get-WmiObject -Class Win32_Printer | Sort-Object Name)
    if ($printers.Count -eq 0) {
        throw 'No Windows printers were found. Install and test the printer before running setup.'
    }

    if ($NonInteractive) {
        return $printers[0].Name
    }

    Write-Host ''
    Write-Host 'Available Windows printers:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $printers.Count; $index++) {
        $number = $index + 1
        Write-Host ("  {0}. {1}" -f $number, $printers[$index].Name)
    }

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $manual = Read-DefaultedInput -Prompt 'Printer name' -DefaultValue $CurrentValue
        return $manual
    }

    while ($true) {
        $choice = Read-Host 'Enter printer number or exact printer name'
        $parsed = 0
        if ([int]::TryParse($choice, [ref]$parsed)) {
            if ($parsed -ge 1 -and $parsed -le $printers.Count) {
                return $printers[$parsed - 1].Name
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($choice)) {
            return $choice.Trim()
        }
        Write-Host 'Please choose a printer.' -ForegroundColor Yellow
    }
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Copy-WorkerScripts {
    param([Parameter(Mandatory = $true)][string]$DestinationScripts)

    $sourceScripts = $PSScriptRoot
    New-DirectoryIfMissing -Path $DestinationScripts
    $scriptNames = @(
        'Invoke-EmailPrintJob.ps1',
        'Invoke-EmailPrintQueue.ps1',
        'Install-EmailPrintScheduledTask.ps1',
        'Test-EmailPrintSetup.ps1'
    )

    foreach ($scriptName in $scriptNames) {
        $source = Join-Path -Path $sourceScripts -ChildPath $scriptName
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Setup package is missing required script: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path -Path $DestinationScripts -ChildPath $scriptName) -Force
    }
}

Write-Host 'Email Print Host Setup' -ForegroundColor Cyan
Write-Host 'This installs the local Windows print worker for the dedicated print PC.'
Write-Host ''

$InstallRoot = Read-DefaultedInput -Prompt 'Install folder' -DefaultValue $InstallRoot
$QueueRoot = Read-DefaultedInput -Prompt 'Local synced queue folder' -DefaultValue $QueueRoot
$DefaultPrinter = Select-PrinterName -CurrentValue $DefaultPrinter
$enablePdfPrinting = Read-YesNo -Prompt 'Enable PDF attachment printing with SumatraPDF?' -DefaultYes $true
if ($enablePdfPrinting) {
    $SumatraPdfPath = Read-DefaultedInput -Prompt 'SumatraPDF path for PDF printing' -DefaultValue $SumatraPdfPath
}
$printEmailBody = Read-YesNo -Prompt 'Print the email body when body.txt exists?' -DefaultYes $true
$printAttachments = Read-YesNo -Prompt 'Print attachments?' -DefaultYes $true
$archiveSuccessfulJobs = Read-YesNo -Prompt 'Move successfully printed jobs to archive?' -DefaultYes $true
$installScheduledTask = -not $NoScheduledTask
if (-not $NoScheduledTask) {
    $installScheduledTask = Read-YesNo -Prompt 'Install Windows Scheduled Task to process the queue every minute?' -DefaultYes $true
}

if ($EveryMinutes -lt 1) {
    throw 'EveryMinutes must be 1 or greater.'
}

$scriptsDestination = Join-Path -Path $InstallRoot -ChildPath 'scripts'
$configPath = Join-Path -Path $InstallRoot -ChildPath 'print-worker.json'

New-DirectoryIfMissing -Path $InstallRoot
New-DirectoryIfMissing -Path $QueueRoot
foreach ($folder in @('incoming', 'archive', 'failed', 'logs')) {
    New-DirectoryIfMissing -Path (Join-Path -Path $QueueRoot -ChildPath $folder)
}
Copy-WorkerScripts -DestinationScripts $scriptsDestination

$supportedExtensions = [ordered]@{}
if ($enablePdfPrinting) {
    $supportedExtensions['.pdf'] = [ordered]@{
        Command = $SumatraPdfPath
        Arguments = @('-print-to', '{Printer}', '-silent', '{File}')
    }
}
$supportedExtensions['.txt'] = [ordered]@{
    Command = 'notepad.exe'
    Arguments = @('/p', '{File}')
}

$config = [ordered]@{
    QueueRoot = $QueueRoot
    IncomingFolder = 'incoming'
    ArchiveFolder = 'archive'
    FailedFolder = 'failed'
    LogFolder = 'logs'
    DefaultPrinter = $DefaultPrinter
    PrintEmailBody = $printEmailBody
    PrintAttachments = $printAttachments
    ArchiveSuccessfulJobs = $archiveSuccessfulJobs
    CommandTimeoutSeconds = 120
    SupportedExtensions = $supportedExtensions
}

$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

Write-Host ''
Write-Host 'Validating setup...' -ForegroundColor Cyan
$testScript = Join-Path -Path $scriptsDestination -ChildPath 'Test-EmailPrintSetup.ps1'
& $testScript -ConfigPath $configPath

if ($installScheduledTask) {
    Write-Host ''
    Write-Host 'Installing scheduled task...' -ForegroundColor Cyan
    $installScript = Join-Path -Path $scriptsDestination -ChildPath 'Install-EmailPrintScheduledTask.ps1'
    & $installScript -ConfigPath $configPath -EveryMinutes $EveryMinutes
}

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "Install folder : $InstallRoot"
Write-Host "Config file    : $configPath"
Write-Host "Queue folder   : $QueueRoot"
Write-Host "Incoming jobs  : $(Join-Path -Path $QueueRoot -ChildPath 'incoming')"
Write-Host "Logs           : $(Join-Path -Path $QueueRoot -ChildPath 'logs\print-worker.csv')"
Write-Host ''
Write-Host 'Next step: configure the Power Automate cloud flow to create job folders in the incoming folder and write .ready last.' -ForegroundColor Yellow
