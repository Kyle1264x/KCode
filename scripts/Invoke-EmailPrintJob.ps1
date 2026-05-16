[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$JobPath,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function ConvertTo-Hashtable {
    param([Parameter(Mandatory = $true)]$InputObject)
    $table = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $table[$property.Name.ToLowerInvariant()] = $property.Value
    }
    return $table
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-UniqueDestinationPath {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $candidate = Join-Path -Path $Directory -ChildPath $Name
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path -Path $Directory -ChildPath ("{0}-{1}" -f $stamp, $Name)
}

function Write-PrintLog {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$JobName,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $logRoot = Join-Path -Path $Config.QueueRoot -ChildPath $Config.LogFolder
    New-DirectoryIfMissing -Path $logRoot
    $logPath = Join-Path -Path $logRoot -ChildPath 'print-worker.csv'
    $record = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Computer  = $env:COMPUTERNAME
        Job       = $JobName
        Status    = $Status
        Detail    = $Detail
    }
    $record | Export-Csv -LiteralPath $logPath -Append -NoTypeInformation
}

function Invoke-ConfiguredPrint {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$SupportedExtensions,
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File
    )

    $extension = $File.Extension.ToLowerInvariant()
    if (-not $SupportedExtensions.ContainsKey($extension)) {
        throw "Unsupported file type '$extension' for file '$($File.FullName)'"
    }

    $rule = $SupportedExtensions[$extension]
    $command = [Environment]::ExpandEnvironmentVariables([string]$rule.Command)
    if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $command -PathType Leaf)) {
        throw "Print command was not found for '$extension': $command"
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $rule.Arguments) {
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$argument)
        $expanded = $expanded.Replace('{File}', $File.FullName).Replace('{Printer}', $Config.DefaultPrinter)
        $arguments.Add($expanded)
    }

    $timeoutSeconds = [int]$Config.CommandTimeoutSeconds
    if ($timeoutSeconds -lt 1) {
        $timeoutSeconds = 120
    }

    $process = Start-Process -FilePath $command -ArgumentList $arguments.ToArray() -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
        try {
            $process.Kill()
        } catch {
            # The process may have exited between WaitForExit and Kill.
        }
        throw "Print command timed out after $timeoutSeconds seconds for '$($File.FullName)'"
    }

    if ($process.ExitCode -ne 0) {
        throw "Print command failed for '$($File.FullName)' with exit code $($process.ExitCode)"
    }
}

$config = Read-JsonFile -Path $ConfigPath
$job = Get-Item -LiteralPath $JobPath
$readyPath = Join-Path -Path $job.FullName -ChildPath '.ready'
if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
    throw "Job is not ready because .ready was not found: $($job.FullName)"
}

$supportedExtensions = ConvertTo-Hashtable -InputObject $config.SupportedExtensions
$printedFiles = New-Object System.Collections.Generic.List[string]

try {
    if ($config.PrintEmailBody) {
        $bodyTxt = Join-Path -Path $job.FullName -ChildPath 'body.txt'
        if (Test-Path -LiteralPath $bodyTxt -PathType Leaf) {
            Invoke-ConfiguredPrint -Config $config -SupportedExtensions $supportedExtensions -File (Get-Item -LiteralPath $bodyTxt)
            $printedFiles.Add($bodyTxt)
        }
    }

    if ($config.PrintAttachments) {
        $attachments = Join-Path -Path $job.FullName -ChildPath 'attachments'
        if (Test-Path -LiteralPath $attachments -PathType Container) {
            Get-ChildItem -LiteralPath $attachments -File | Sort-Object Name | ForEach-Object {
                Invoke-ConfiguredPrint -Config $config -SupportedExtensions $supportedExtensions -File $_
                $printedFiles.Add($_.FullName)
            }
        }
    }

    if ($printedFiles.Count -eq 0) {
        throw "No printable files were found in job '$($job.FullName)'"
    }

    Write-PrintLog -Config $config -JobName $job.Name -Status 'Printed' -Detail ($printedFiles -join '; ')

    if ($config.ArchiveSuccessfulJobs) {
        $archiveRoot = Join-Path -Path $config.QueueRoot -ChildPath $config.ArchiveFolder
        New-DirectoryIfMissing -Path $archiveRoot
        $destination = Get-UniqueDestinationPath -Directory $archiveRoot -Name $job.Name
        Move-Item -LiteralPath $job.FullName -Destination $destination -Force
    }
} catch {
    $failedRoot = Join-Path -Path $config.QueueRoot -ChildPath $config.FailedFolder
    New-DirectoryIfMissing -Path $failedRoot
    Set-Content -LiteralPath (Join-Path -Path $job.FullName -ChildPath 'error.txt') -Value $_.Exception.Message
    Write-PrintLog -Config $config -JobName $job.Name -Status 'Failed' -Detail $_.Exception.Message
    $destination = Get-UniqueDestinationPath -Directory $failedRoot -Name $job.Name
    Move-Item -LiteralPath $job.FullName -Destination $destination -Force
    throw
}
