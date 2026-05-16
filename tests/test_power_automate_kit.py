from __future__ import annotations

import json
from pathlib import Path

SCRIPTS = Path("scripts")

def test_config_template_has_required_windows_queue_and_print_settings() -> None:
    config = json.loads(Path("config/print-worker.example.json").read_text(encoding="utf-8"))

    assert config["QueueRoot"] == "C:\\EmailPrintQueue"
    assert config["IncomingFolder"] == "incoming"
    assert config["ArchiveFolder"] == "archive"
    assert config["FailedFolder"] == "failed"
    assert config["LogFolder"] == "logs"
    assert config["DefaultPrinter"]
    assert config["CommandTimeoutSeconds"] > 0
    assert ".pdf" in config["SupportedExtensions"]
    assert "SumatraPDF.exe" in config["SupportedExtensions"][".pdf"]["Command"]

def test_worker_scripts_are_windows_powershell_compatible_and_safe() -> None:
    job_script = (SCRIPTS / "Invoke-EmailPrintJob.ps1").read_text(encoding="utf-8")
    queue_script = (SCRIPTS / "Invoke-EmailPrintQueue.ps1").read_text(encoding="utf-8")

    assert "Set-StrictMode -Version 2.0" in job_script
    assert "Set-StrictMode -Version 2.0" in queue_script
    assert "'.ready'" in job_script
    assert "Job is not ready" in job_script
    assert "WaitForExit($timeoutSeconds * 1000)" in job_script
    assert "print-worker.lock" in queue_script
    assert "[System.IO.FileShare]::None" in queue_script

def test_windows_helper_scripts_exist_for_install_validation_and_easy_setup() -> None:
    install_script = (SCRIPTS / "Install-EmailPrintScheduledTask.ps1").read_text(encoding="utf-8")
    setup_script = (SCRIPTS / "Test-EmailPrintSetup.ps1").read_text(encoding="utf-8")
    host_setup = (SCRIPTS / "Setup-EmailPrintHost.ps1").read_text(encoding="utf-8")
    cmd_launcher = Path("Setup-EmailPrintHost.cmd").read_text(encoding="utf-8")
    package_launcher = Path("Build-EmailPrintHostPackage.cmd").read_text(encoding="utf-8")
    package_script = (SCRIPTS / "Build-EmailPrintHostPackage.ps1").read_text(encoding="utf-8")

    assert "Register-ScheduledTask" in install_script
    assert "New-ScheduledTaskTrigger" in install_script
    assert "powershell.exe" in install_script
    assert "Get-WmiObject -Class Win32_Printer" in setup_script
    assert "Email print setup check passed" in setup_script
    assert "Select-PrinterName" in host_setup
    assert "Copy-WorkerScripts" in host_setup
    assert "unresolved merge conflict markers" in host_setup
    assert "Install-WingetPackage" in host_setup
    assert "SumatraPDF.SumatraPDF" in host_setup
    assert "Microsoft.OneDrive" in host_setup
    assert "SkipToolInstall" in host_setup
    assert "MailboxAddress = 'abricoh@outlook.com'" in host_setup
    assert "power-automate-flow-settings.json" in host_setup
    assert "NonInteractive" in host_setup
    assert "Setup-EmailPrintHost.ps1" in cmd_launcher
    assert "Write-SetupHint" in host_setup
    assert "how to find" in host_setup
    assert "Build-EmailPrintHostPackage.ps1" in package_launcher
    assert "Compress-Archive" in package_script
    assert "Compress-Archive -Path" in package_script
    assert "Compress-Archive -LiteralPath" not in package_script
    assert "START-HERE.txt" in package_script

def test_documentation_describes_windows_cloud_flow_contract() -> None:
    readme = Path("README.md").read_text(encoding="utf-8")
    setup = Path("docs/power-automate-setup.md").read_text(encoding="utf-8")

    assert "dedicated Windows print PC" in readme
    assert "Windows PowerShell 5.1" in readme
    assert "The `.ready` file must be the **last** file" in readme
    assert "When a new email arrives" in setup
    assert "abricoh@outlook.com" in setup
    assert "do not" in setup.lower() and "password" in setup.lower()
    assert "Windows Task Scheduler" in setup
    assert "Test-EmailPrintSetup.ps1" in setup
    assert "Setup-EmailPrintHost.cmd" in readme
    assert "NonInteractive" in setup
    assert "winget" in setup
    assert "EmailPrintHostSetup.zip" in readme
    assert "Each prompt" in setup

def test_cloud_flow_settings_are_for_client_mailbox_without_password() -> None:
    settings_text = Path("config/power-automate-flow-settings.example.json").read_text(
        encoding="utf-8"
    )
    settings = json.loads(settings_text)

    assert settings["MailboxAddress"] == "abricoh@outlook.com"
    assert settings["ReadyMarkerName"] == ".ready"
    assert "password" not in settings_text.lower()

def test_conflict_prone_files_have_no_merge_markers() -> None:
    conflict_prone_files = [
        Path(".gitignore"),
        Path("README.md"),
        Path("docs/power-automate-setup.md"),
        Path("scripts/Setup-EmailPrintHost.ps1"),
        Path("tests/test_power_automate_kit.py"),
    ]
    for path in conflict_prone_files:
        lines = path.read_text(encoding="utf-8").splitlines()
        assert not any(
            line.startswith("<<<<<<<") or line == "=======" or line.startswith(">>>>>>>")
            for line in lines
        ), path
