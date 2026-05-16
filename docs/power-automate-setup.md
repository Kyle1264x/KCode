# Power Automate + Dedicated Windows Print PC Setup

Use this build when the client wants a fast, reliable replacement for Outlook/Sperry-style auto-printing and already has a dedicated small Windows PC available.

## 1. Windows requirements

- Windows 10/11 Pro or a supported Windows Server version.
- Windows PowerShell 5.1, which ships with modern Windows.
- A local Windows user that stays signed in if you use OneDrive sync plus Task Scheduler.
- The target printer installed and tested for that same Windows user.
- OneDrive sync or SharePoint sync for the queue folder. Setup can install OneDrive if it is missing, but you still need to sign in and choose the synced queue folder.
- SumatraPDF installed if PDF attachments need silent printing. Setup can install it automatically with `winget`.

Microsoft's current guidance distinguishes attended and unattended desktop automation. If a cloud flow directly triggers a desktop flow without a user supervising it, plan for unattended desktop flow requirements and capacity. Microsoft notes that unattended desktop flows run in a Windows session Power Automate creates and that Windows 10/11 unattended runs require no active Windows user session on the target machine. See Microsoft's unattended desktop flow documentation: <https://learn.microsoft.com/en-us/power-automate/desktop-flows/run-unattended-desktop-flows>.

If licensing or unattended-session behavior is a concern, use the scheduled-task pattern instead: the cloud flow only saves files to OneDrive/SharePoint, and Windows Task Scheduler runs the local queue worker every minute on the signed-in print PC. Microsoft also documents that Power Automate Desktop includes workstation actions such as **Print document**, **Set default printer**, and **Get default printer**: <https://learn.microsoft.com/en-us/power-automate/desktop-flows/actions-reference/workstation>.

## 2. Dedicated print PC preparation

1. Give the PC a stable name, stable power settings, and a reliable network connection.
2. Sign in as the Windows user that will own the OneDrive sync and scheduled task.
3. Install the printer driver locally and print a test page.
4. Capture the exact printer name from Windows **Settings > Bluetooth & devices > Printers & scanners** or from PowerShell:

   ```powershell
   Get-Printer | Select-Object Name
   ```

5. Copy this repository folder to the PC and run `Setup-EmailPrintHost.cmd`.
6. Let setup install OneDrive and SumatraPDF if they are missing.
7. Sign in to OneDrive and sync the chosen queue folder, or sync the SharePoint document library.
8. Setup creates `C:\EmailPrint`, `print-worker.json`, and the queue root for you. By default, the queue root is `C:\EmailPrintQueue` with these subfolders:
   - `incoming`
   - `archive`
   - `failed`
   - `logs`

## 3. Build one easy setup package

For the easiest download/copy experience, build a zip package first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-EmailPrintHostPackage.ps1
```

This creates `dist\EmailPrintHostSetup.zip`. Copy that zip to the print PC, extract it, open `START-HERE.txt` if needed, then run the setup launcher.

## 4. Run the easy host setup

The easiest path on the Windows print PC is to run the setup launcher:

```powershell
Setup-EmailPrintHost.cmd
```

You can also run the PowerShell installer directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1
```

The setup asks for the items below. Each prompt includes short help text explaining what the value is and how to find it:

- install folder, usually `C:\EmailPrint`
- local synced queue folder, usually `C:\EmailPrintQueue`
- Outlook mailbox, defaulting to `abricoh@outlook.com`
- Windows printer, selected from detected printers or entered manually
- whether to enable PDF attachment printing
- SumatraPDF path for PDF printing, if PDF printing is enabled
- whether to print email bodies
- whether to print attachments
- whether to archive successful jobs
- whether to install missing tools automatically with `winget`
- whether to install the scheduled task

The setup creates the queue folders, copies scripts to the install folder, checks for SumatraPDF and OneDrive, installs missing tools with Windows Package Manager (`winget`) when you approve it, writes `print-worker.json` and `power-automate-flow-settings.json`, validates the printer and print commands, and can install the recurring scheduled task.

Non-interactive install example for repeat deployments:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1 -InstallRoot C:\EmailPrint -QueueRoot C:\EmailPrintQueue -DefaultPrinter "Front Office Printer" -MailboxAddress abricoh@outlook.com -SumatraPdfPath "C:\Program Files\SumatraPDF\SumatraPDF.exe" -EveryMinutes 1 -NonInteractive
```

If you want setup to create folders and config but **not** install missing tools, add `-SkipToolInstall`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1 -SkipToolInstall
```

## 5. Manual configuration and validation

If you do not want to use the easy setup, edit `C:\EmailPrint\print-worker.json` manually:

- Set `QueueRoot` to the local synced folder path.
- Set `DefaultPrinter` to the exact Windows printer name.
- Confirm `C:\Program Files\SumatraPDF\SumatraPDF.exe` exists, or update the `.pdf` command path.
- Remove file extensions that should not be printed automatically.

Run the setup validator on the print PC:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EmailPrint\scripts\Test-EmailPrintSetup.ps1 -ConfigPath C:\EmailPrint\print-worker.json
```

The validator confirms the queue root exists, the printer is installed, and every configured print command is available on Windows.

## 6. Cloud flow design

Create an automated cloud flow for `abricoh@outlook.com`. Do **not** paste the Outlook password into these scripts, the repository, or the generated job files. Power Automate should authenticate the mailbox through Microsoft's Outlook connector sign-in prompt/OAuth connection.

1. Trigger: **When a new email arrives** for the Outlook mailbox `abricoh@outlook.com`.
2. Add guard conditions:
   - Optional sender allow-list.
   - Optional subject keyword or category filter.
   - Optional attachment-required check.
3. Use the settings in `config/power-automate-flow-settings.example.json` as the cloud-flow naming contract.
4. Compose a unique `JobId`, for example:
   - received timestamp formatted as `yyyyMMdd-HHmmss`
   - message id hash or short GUID
5. Create folder: `EmailPrintQueue/incoming/<JobId>`.
6. Create folder: `EmailPrintQueue/incoming/<JobId>/attachments`.
7. Create `job.json` containing metadata such as sender, subject, received time, message id, and attachment count.
8. Create `body.txt` from the email body if email-body printing is required.
9. For each attachment, create a file under `attachments` using the attachment name.
10. Create `.ready` as the final file in the job folder.
11. Move the email to a mailbox folder such as `Queued for Print` or mark it with a category.

The `.ready` marker is important because OneDrive/SharePoint sync can expose a folder before all files are present. The local worker ignores folders until `.ready` exists.

### Password and account handling

You can provide the password when you are physically setting up the Power Automate Outlook connection, but do not send it in chat and do not save it in this repo. The local Windows print worker does not need the Outlook password. The only component that signs into `abricoh@outlook.com` is the Power Automate cloud flow connection.

## 7. Recommended Windows Task Scheduler pattern

For your dedicated small PC, this is usually the fastest reliable setup. The cloud flow creates job folders; the local Windows task polls the synced folder every minute.

Install the scheduled task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EmailPrint\scripts\Install-EmailPrintScheduledTask.ps1 -ConfigPath C:\EmailPrint\print-worker.json
```

The task runs as the current Windows user with `Interactive` logon type. Keep that user signed in so OneDrive sync and printer access remain available. The queue script also uses `print-worker.lock` to avoid overlapping task runs.

Manual one-time queue run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EmailPrint\scripts\Invoke-EmailPrintQueue.ps1 -ConfigPath C:\EmailPrint\print-worker.json
```

## 8. Optional Power Automate Desktop pattern

If you have unattended Power Automate Desktop capacity, the cloud flow can run a desktop flow on the print PC after it creates `.ready`.

Recommended desktop flow actions:

1. Input variable: `JobPath`.
2. Action: **Run PowerShell script**.
3. Script path/command:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\EmailPrint\scripts\Invoke-EmailPrintJob.ps1 -JobPath "%JobPath%" -ConfigPath C:\EmailPrint\print-worker.json
   ```

4. Return the exit code and standard error to the cloud flow.
5. If successful, move or categorize the original email as `Printed`.
6. If failed, move or categorize the original email as `Print Failed` and send an alert.

Power Automate Desktop also has a built-in **Print document** workstation action, but this kit uses an explicit PowerShell worker so file-type handling, logging, archiving, timeout handling, and failures are consistent.

## 9. File type policy

Start with PDFs only if possible. Add other extensions only after testing them on the print PC.

Recommended initial policy:

- `.pdf`: supported with SumatraPDF.
- `.txt`: supported with Notepad for simple text.
- Office files: convert to PDF before printing, or add a controlled LibreOffice/Microsoft Office conversion process later.
- Images: add only after testing a dedicated image-print command.
- ZIP files: do not auto-print; route to failed/manual review.

## 10. Support process

Daily checks:

- Confirm `failed` is empty.
- Confirm `logs\print-worker.csv` has successful entries.
- Confirm OneDrive/SharePoint sync is healthy.
- Confirm the printer queue is not paused or offline.
- Confirm the Windows scheduled task last-run result is successful.

Failure triage:

1. Open the failed job folder.
2. Review `error.txt`.
3. Check whether the attachment extension is supported in `print-worker.json`.
4. Print the file manually from the print PC.
5. If manual printing works, add or adjust the command in `print-worker.json`.
6. Move the corrected job back to `incoming` and recreate `.ready` to retry.

## 11. Publishing and conflict checks

If GitHub or your Git client says the branch has conflicts, check the files it lists for merge markers before publishing:

```bash
rg -n "^(<<<<<<<|=======$|>>>>>>>)" .gitignore README.md docs/power-automate-setup.md scripts/Setup-EmailPrintHost.ps1 tests/test_power_automate_kit.py
python3 -m pytest -q
git diff --check
```

The `rg` command should return no results. If it does, remove the marker block by keeping the intended final text and deleting the `<<<<<<<`, `=======`, and `>>>>>>>` lines.
