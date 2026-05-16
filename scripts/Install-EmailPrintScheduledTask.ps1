[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigPath,

    [string]$TaskName = 'Email Print Queue Worker',

    [int]$EveryMinutes = 1
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($EveryMinutes -lt 1) {
    throw 'EveryMinutes must be 1 or greater.'
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$queueScript = Join-Path -Path $scriptRoot -ChildPath 'Invoke-EmailPrintQueue.ps1'
if (-not (Test-Path -LiteralPath $queueScript -PathType Leaf)) {
    throw "Queue script was not found: $queueScript"
}

$powerShell = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$queueScript`" -ConfigPath `"$ConfigPath`""
$action = New-ScheduledTaskAction -Execute $powerShell -Argument $argument
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel LeastPrivilege

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "Scheduled task '$TaskName' installed for user '$currentUser'."
Write-Host "The Windows user must stay signed in so OneDrive sync and printer access are available."
