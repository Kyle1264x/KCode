# Power Automate Email-to-Print Kit for Windows

This repository implements **Option 1: Power Automate + a dedicated Windows print PC**. It avoids Outlook desktop rules/add-ins by using Microsoft 365 as the intake queue, Power Automate as the email trigger, OneDrive/SharePoint sync as the handoff, and Windows PowerShell scripts on the dedicated PC as the local print worker.

## Architecture

```text
Sender emails abricoh@outlook.com
        │
        ▼
Power Automate cloud flow watches abricoh@outlook.com
Sender emails printbox@clientdomain.com
        │
        ▼
Power Automate cloud flow watches the mailbox
        │
        ▼
Cloud flow creates one job folder in OneDrive/SharePoint
        │
        ▼
Dedicated Windows print PC syncs the folder locally
        │
        ▼
Windows Task Scheduler or Power Automate Desktop invokes scripts\Invoke-EmailPrintQueue.ps1
        │
        ▼
scripts\Invoke-EmailPrintJob.ps1 prints, logs, archives successes, and moves failures
```

## Windows-first design choices

- Scripts target **Windows PowerShell 5.1**, which is included with Windows 10/11 and Windows Server.
- The worker uses Windows paths, `Start-Process`, Windows printer names, and Task Scheduler.
- The queue worker creates a lock file so overlapping scheduled-task runs do not print the same job twice.
- Every email job must include a `.ready` marker. The print PC ignores folders until that marker exists.
- Only extensions listed in `SupportedExtensions` print automatically.
- The default PDF example uses SumatraPDF's silent `-print-to` command.

## Repository contents

- [`docs/power-automate-setup.md`](docs/power-automate-setup.md): full Windows setup checklist.
- [`config/print-worker.example.json`](config/print-worker.example.json): Windows print worker configuration template.
- [`config/power-automate-flow-settings.example.json`](config/power-automate-flow-settings.example.json): cloud-flow settings for the `abricoh@outlook.com` mailbox.
- [`Setup-EmailPrintHost.cmd`](Setup-EmailPrintHost.cmd): double-click launcher for the interactive Windows setup.
- [`Build-EmailPrintHostPackage.cmd`](Build-EmailPrintHostPackage.cmd): double-click package builder that creates `dist\EmailPrintHostSetup.zip` for easy download/copy to the print PC.
- [`scripts/Setup-EmailPrintHost.ps1`](scripts/Setup-EmailPrintHost.ps1): interactive/non-interactive installer that asks for the mailbox, printer, queue folder, install folder, and PDF tool path, then creates folders, installs missing tools with `winget`, writes local and cloud-flow config, validates, and installs the scheduled task.
- [`Setup-EmailPrintHost.cmd`](Setup-EmailPrintHost.cmd): double-click launcher for the interactive Windows setup.
- [`scripts/Setup-EmailPrintHost.ps1`](scripts/Setup-EmailPrintHost.ps1): interactive/non-interactive installer that asks for the printer, queue folder, install folder, and PDF tool path.
- [`scripts/Test-EmailPrintSetup.ps1`](scripts/Test-EmailPrintSetup.ps1): validates printer, queue folder, and configured print commands on the PC.
- [`scripts/Install-EmailPrintScheduledTask.ps1`](scripts/Install-EmailPrintScheduledTask.ps1): installs the recurring local queue worker task.
- [`scripts/Invoke-EmailPrintQueue.ps1`](scripts/Invoke-EmailPrintQueue.ps1): scans for ready jobs and invokes the per-job script.
- [`scripts/Invoke-EmailPrintJob.ps1`](scripts/Invoke-EmailPrintJob.ps1): prints one completed job folder.

## Job folder contract

The Power Automate cloud flow for `abricoh@outlook.com` should create this shape under the synced queue root:
The Power Automate cloud flow should create this shape under the synced queue root:

```text
EmailPrintQueue\
  incoming\
    20260516-135501-a1b2c3d4\
      job.json
      body.txt
      attachments\
        invoice.pdf
        label.pdf
      .ready
  archive\
  failed\
  logs\
```

The `.ready` file must be the **last** file the cloud flow creates. This protects the print PC from printing a job before OneDrive/SharePoint has synced every file.

## Quick start on the dedicated Windows print PC

1. Install and test the printer in Windows.
2. If you want a single download/copy artifact, double-click `Build-EmailPrintHostPackage.cmd` and use `dist\EmailPrintHostSetup.zip`.
3. Copy/extract the package folder on the print PC.
4. Double-click `Setup-EmailPrintHost.cmd`, or run the PowerShell setup directly.
5. Answer the prompts. Each prompt explains what the value is and how to find it.
6. If SumatraPDF or OneDrive are missing, let setup install them automatically with Windows Package Manager (`winget`).
7. Sign in to OneDrive and sync the queue folder locally if setup installed or opened OneDrive for you.
8. Drop a test job folder with `.ready` into `C:\EmailPrintQueue\incoming` and confirm it moves to `archive` or `failed`.
2. Install OneDrive and sync the queue folder locally, for example `C:\EmailPrintQueue`.
3. Install SumatraPDF if PDFs need to print silently.
4. Download or copy this repository folder to the print PC.
5. Double-click `Setup-EmailPrintHost.cmd`, or run the PowerShell setup directly.
6. Enter the requested values when prompted: install folder, queue folder, printer, whether to enable PDF printing, SumatraPDF path, and whether to install the scheduled task.
7. Drop a test job folder with `.ready` into `C:\EmailPrintQueue\incoming` and confirm it moves to `archive` or `failed`.

Interactive setup command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1
```

Non-interactive example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1 -InstallRoot C:\EmailPrint -QueueRoot C:\EmailPrintQueue -DefaultPrinter "Front Office Printer" -MailboxAddress abricoh@outlook.com -SumatraPdfPath "C:\Program Files\SumatraPDF\SumatraPDF.exe" -EveryMinutes 1 -NonInteractive
```

## Build one easy setup package

From the repo folder on any Windows machine, double-click `Build-EmailPrintHostPackage.cmd` or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-EmailPrintHostPackage.ps1
```

This creates `dist\EmailPrintHostSetup.zip`. Send that zip to the print PC, extract it, then double-click `Setup-EmailPrintHost.cmd`.

## Publish/conflict checks

Before publishing the branch or building the zip, run these checks from the repo root:

```bash
python3 -m ruff check .
python3 -m pytest -q
git diff --check
rg -n "^(<<<<<<<|=======$|>>>>>>>)" .
```

The final `rg` command should return no results. The setup script also refuses to copy worker scripts that contain unresolved merge conflict markers.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1 -InstallRoot C:\EmailPrint -QueueRoot C:\EmailPrintQueue -DefaultPrinter "Front Office Printer" -SumatraPdfPath "C:\Program Files\SumatraPDF\SumatraPDF.exe" -EveryMinutes 1 -NonInteractive
```

## Manual worker commands

Process the whole queue once:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EmailPrint\scripts\Invoke-EmailPrintQueue.ps1 -ConfigPath C:\EmailPrint\print-worker.json
```

Process one job folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EmailPrint\scripts\Invoke-EmailPrintJob.ps1 -JobPath C:\EmailPrintQueue\incoming\example-job -ConfigPath C:\EmailPrint\print-worker.json
```

See [`docs/power-automate-setup.md`](docs/power-automate-setup.md) for the full build checklist and Power Automate flow steps. Do **not** put the Outlook password in this repository or in these scripts; Power Automate should connect to `abricoh@outlook.com` using Microsoft's normal sign-in/OAuth prompt.
See [`docs/power-automate-setup.md`](docs/power-automate-setup.md) for the full build checklist and Power Automate flow steps.
