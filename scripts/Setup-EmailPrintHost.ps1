[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\EmailPrint',
    [string]$QueueRoot = 'C:\EmailPrintQueue',
    [string]$DefaultPrinter = '',
    [string]$MailboxAddress = 'abricoh@outlook.com',
    [string]$SumatraPdfPath = 'C:\Program Files\SumatraPDF\SumatraPDF.exe',
    [int]$EveryMinutes = 1,
    [switch]$NoScheduledTask,
    [switch]$SkipToolInstall,
    [string]$SumatraPdfPath = 'C:\Program Files\SumatraPDF\SumatraPDF.exe',
    [int]$EveryMinutes = 1,
    [switch]$NoScheduledTask,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-SetupHint {
    param([Parameter(Mandatory = $true)][string]$Message)
    if (-not $NonInteractive) {
        Write-Host ''
        Write-Host $Message -ForegroundColor DarkCyan
    }
}

function Read-DefaultedInput {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$DefaultValue,
        [string]$HelpText = ''
function Read-DefaultedInput {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if ($NonInteractive) {
        return $DefaultValue
    }

    if (-not [string]::IsNullOrWhiteSpace($HelpText)) {
        Write-SetupHint -Message $HelpText
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
        [bool]$DefaultYes = $true,
        [string]$HelpText = ''
        [bool]$DefaultYes = $true
    )

    if ($NonInteractive) {
        return $DefaultYes
    }

    if (-not [string]::IsNullOrWhiteSpace($HelpText)) {
        Write-SetupHint -Message $HelpText
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

    Write-SetupHint -Message 'Printer: choose the Windows printer that should receive these email jobs. If you are not sure, open Settings > Bluetooth & devices > Printers & scanners, print a test page, and use that exact printer name.'
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

function Get-WingetPath {
    $winget = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -ne $winget) {
        return $winget.Source
    }

    $windowsAppsWinget = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $windowsAppsWinget -PathType Leaf) {
        return $windowsAppsWinget
    }

    return $null
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$FriendlyName
    )

    $winget = Get-WingetPath
    if ($null -eq $winget) {
        throw "Windows Package Manager winget was not found. Install '$FriendlyName' manually or install winget from Microsoft App Installer, then rerun setup."
    }

    Write-Host "Installing $FriendlyName with winget..." -ForegroundColor Cyan
    $arguments = @(
        'install',
        '--id', $PackageId,
        '--exact',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )
    $process = Start-Process -FilePath $winget -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "winget failed to install $FriendlyName. Exit code: $($process.ExitCode)"
    }
}

function Resolve-SumatraPdfPath {
    param([Parameter(Mandatory = $true)][string]$PreferredPath)

    $candidates = @(
        $PreferredPath,
        'C:\Program Files\SumatraPDF\SumatraPDF.exe',
        'C:\Program Files (x86)\SumatraPDF\SumatraPDF.exe',
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SumatraPDF\SumatraPDF.exe')
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
            if (Test-Path -LiteralPath $expanded -PathType Leaf) {
                return $expanded
            }
        }
    }

    return $PreferredPath
}

function Ensure-SumatraPdfInstalled {
    param([Parameter(Mandatory = $true)][string]$PreferredPath)

    $resolved = Resolve-SumatraPdfPath -PreferredPath $PreferredPath
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        Write-Host "Found SumatraPDF: $resolved" -ForegroundColor Green
        return $resolved
    }

    if ($SkipToolInstall) {
        throw "SumatraPDF was not found at '$PreferredPath' and SkipToolInstall was specified. Install SumatraPDF or rerun without -SkipToolInstall."
    }

    $shouldInstall = Read-YesNo -Prompt 'SumatraPDF was not found. Install it automatically with winget?' -DefaultYes $true
    if (-not $shouldInstall) {
        throw 'PDF printing is enabled, but SumatraPDF is not installed.'
    }

    Install-WingetPackage -PackageId 'SumatraPDF.SumatraPDF' -FriendlyName 'SumatraPDF'
    $resolved = Resolve-SumatraPdfPath -PreferredPath $PreferredPath
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "SumatraPDF install completed, but SumatraPDF.exe was not found. Update print-worker.json with the installed path."
    }
    return $resolved
}

function Ensure-OneDriveAvailable {
    $candidates = @(
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\OneDrive\OneDrive.exe'),
        'C:\Program Files\Microsoft OneDrive\OneDrive.exe',
        'C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Write-Host "Found OneDrive: $candidate" -ForegroundColor Green
            return $candidate
        }
    }

    if ($SkipToolInstall) {
        Write-Host 'OneDrive was not found. Skipping install because SkipToolInstall was specified.' -ForegroundColor Yellow
        return $null
    }

    $shouldInstall = Read-YesNo -Prompt 'OneDrive was not found. Install it automatically with winget?' -DefaultYes $true
    if (-not $shouldInstall) {
        Write-Host 'Skipping OneDrive install. Make sure your queue folder is synced another way.' -ForegroundColor Yellow
        return $null
    }

    Install-WingetPackage -PackageId 'Microsoft.OneDrive' -FriendlyName 'Microsoft OneDrive'
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Write-Host "Found OneDrive after install: $candidate" -ForegroundColor Green
            Start-Process -FilePath $candidate -ErrorAction SilentlyContinue
            return $candidate
        }
    }
    Write-Host 'OneDrive install finished. Open OneDrive and sign in if it did not start automatically.' -ForegroundColor Yellow
    return $null
}

function Copy-WorkerScripts {
    param([Parameter(Mandatory = $true)][string]$DestinationScripts)

    $sourceScripts = $PSScriptRoot
    New-DirectoryIfMissing -Path $DestinationScripts
    $scriptNames = @(
        'Invoke-EmailPrintJob.ps1',
        'Invoke-EmailPrintQueue.ps1',
        'Install-EmailPrintScheduledTask.ps1',
        'Test-EmailPrintSetup.ps1',
        'Setup-EmailPrintHost.ps1'
        'Test-EmailPrintSetup.ps1'
    )

    foreach ($scriptName in $scriptNames) {
        $source = Join-Path -Path $sourceScripts -ChildPath $scriptName
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Setup package is missing required script: $source"
        }
        $sourceContent = Get-Content -LiteralPath $source -Raw
        if ($sourceContent -match '(?m)^(<<<<<<<|=======$|>>>>>>>)') {
            throw "Setup package contains unresolved merge conflict markers in: $source"
        }
        $destination = Join-Path -Path $DestinationScripts -ChildPath $scriptName
        if ([System.IO.Path]::GetFullPath($source) -ne [System.IO.Path]::GetFullPath($destination)) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path -Path $DestinationScripts -ChildPath $scriptName) -Force
    }
}

Write-Host 'Email Print Host Setup' -ForegroundColor Cyan
Write-Host 'This installs the local Windows print worker for the dedicated print PC.'
Write-Host 'Prompts include notes about how to find each value you need.'
Write-Host ''

if ($PSVersionTable.PSEdition -ne 'Desktop' -and $PSVersionTable.PSVersion.Major -lt 5) {
    throw 'This setup must run in Windows PowerShell 5.1 or newer.'
}
$isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
if ($null -ne $isWindowsVariable -and -not $isWindowsVariable.Value) {
    throw 'This setup script is intended for Windows only.'
}

$InstallRoot = Read-DefaultedInput -Prompt 'Install folder' -DefaultValue $InstallRoot -HelpText 'Install folder: this is where the worker scripts and generated config will live on this PC. The default C:\EmailPrint is recommended.'
$QueueRoot = Read-DefaultedInput -Prompt 'Local synced queue folder' -DefaultValue $QueueRoot -HelpText 'Queue folder: this is the local folder the print PC watches. If using OneDrive/SharePoint, open File Explorer after syncing the library, click the folder, and copy the local path from the address bar. The default C:\EmailPrintQueue works for a local-only queue.'
$MailboxAddress = Read-DefaultedInput -Prompt 'Outlook mailbox for Power Automate' -DefaultValue $MailboxAddress -HelpText 'Outlook mailbox: this is the mailbox the Power Automate cloud flow watches. Sign into this mailbox only in Microsoft Power Automate; do not save the password here.'
$DefaultPrinter = Select-PrinterName -CurrentValue $DefaultPrinter
$enablePdfPrinting = Read-YesNo -Prompt 'Enable PDF attachment printing with SumatraPDF?' -DefaultYes $true -HelpText 'PDF printing: most email attachments are PDFs. Setup can install SumatraPDF automatically if it is missing; SumatraPDF is used because it supports silent printing to a named printer.'
if ($enablePdfPrinting) {
    $SumatraPdfPath = Read-DefaultedInput -Prompt 'SumatraPDF path for PDF printing' -DefaultValue $SumatraPdfPath -HelpText 'SumatraPDF path: if already installed, this is usually C:\Program Files\SumatraPDF\SumatraPDF.exe. If you are not sure, accept the default and setup will find or install it.'
    $SumatraPdfPath = Ensure-SumatraPdfInstalled -PreferredPath $SumatraPdfPath
}
Ensure-OneDriveAvailable | Out-Null
$printEmailBody = Read-YesNo -Prompt 'Print the email body when body.txt exists?' -DefaultYes $true -HelpText 'Email body printing: choose Yes if the message text itself should print in addition to attachments. Choose No if only attachments should print.'
$printAttachments = Read-YesNo -Prompt 'Print attachments?' -DefaultYes $true -HelpText 'Attachment printing: choose Yes for the normal workflow. The worker only prints attachment file types listed in print-worker.json.'
$archiveSuccessfulJobs = Read-YesNo -Prompt 'Move successfully printed jobs to archive?' -DefaultYes $true -HelpText 'Archive successful jobs: choose Yes so completed jobs move out of incoming and can be reviewed later in the archive folder.'
$installScheduledTask = -not $NoScheduledTask
if (-not $NoScheduledTask) {
    $installScheduledTask = Read-YesNo -Prompt 'Install Windows Scheduled Task to process the queue every minute?' -DefaultYes $true -HelpText 'Scheduled Task: choose Yes for hands-off operation. Windows will run the queue worker every minute while this user is signed in.'
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
$cloudFlowSettingsPath = Join-Path -Path $InstallRoot -ChildPath 'power-automate-flow-settings.json'

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

$cloudFlowSettings = [ordered]@{
    MailboxAddress = $MailboxAddress
    QueueRootName = 'EmailPrintQueue'
    IncomingFolder = 'incoming'
    AttachmentFolder = 'attachments'
    ReadyMarkerName = '.ready'
    EmailBodyFileName = 'body.txt'
    JobMetadataFileName = 'job.json'
    QueuedMailboxFolder = 'Queued for Print'
    PrintedMailboxFolder = 'Printed'
    FailedMailboxFolder = 'Print Failed'
}
$cloudFlowSettings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cloudFlowSettingsPath -Encoding UTF8

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
Write-Host "Cloud settings : $cloudFlowSettingsPath"
Write-Host "Mailbox        : $MailboxAddress"
Write-Host "Queue folder   : $QueueRoot"
Write-Host "Incoming jobs  : $(Join-Path -Path $QueueRoot -ChildPath 'incoming')"
Write-Host "Logs           : $(Join-Path -Path $QueueRoot -ChildPath 'logs\print-worker.csv')"
Write-Host ''
Write-Host 'Next step: configure the Power Automate cloud flow for the mailbox above. Sign in through Microsoft; do not save the mailbox password in these files.' -ForegroundColor Yellow
Write-Host 'The cloud flow must create job folders in the incoming folder and write .ready last.' -ForegroundColor Yellow
Write-Host 'Next step: configure the Power Automate cloud flow to create job folders in the incoming folder and write .ready last.' -ForegroundColor Yellow
