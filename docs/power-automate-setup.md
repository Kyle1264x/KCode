# Power Automate + Dedicated Windows Print PC Setup

Use this build when the client wants a fast, reliable replacement for Outlook/Sperry-style auto-printing and already has a dedicated small Windows PC available.

## 1. Windows requirements

- Windows 10/11 Pro or a supported Windows Server version.
- Windows PowerShell 5.1, which ships with modern Windows.
- A local Windows user that stays signed in if you use OneDrive sync plus Task Scheduler.
- The target printer installed and tested for that same Windows user.
- OneDrive sync or SharePoint sync for the queue folder.
- SumatraPDF installed if PDF attachments need silent printing.

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

5. Install OneDrive and sync the chosen queue folder, or sync the SharePoint document library.
6. Install SumatraPDF for silent PDF printing if PDFs are required.
7. Create `C:\EmailPrint` and copy this repository's `scripts` folder there.
8. Copy `config\print-worker.example.json` to `C:\EmailPrint\print-worker.json`.
9. Create the queue root, for example `C:\EmailPrintQueue`, with these subfolders:
   - `incoming`
   - `archive`
   - `failed`
   - `logs`

## 3. Run the easy host setup

The easiest path is to copy this repository folder to the Windows print PC and run the setup launcher:

```powershell
Setup-EmailPrintHost.cmd
```

You can also run the PowerShell installer directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1
```

The setup asks for:

- install folder, usually `C:\EmailPrint`
- local synced queue folder, usually `C:\EmailPrintQueue`
- Windows printer, selected from detected printers or entered manually
- whether to enable PDF attachment printing
- SumatraPDF path for PDF printing, if PDF printing is enabled
- whether to print email bodies
- whether to print attachments
- whether to archive successful jobs
- whether to install the scheduled task

The setup creates the queue folders, copies scripts to the install folder, writes `print-worker.json`, validates the printer and print commands, and can install the recurring scheduled task.

Non-interactive install example for repeat deployments:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-EmailPrintHost.ps1 -InstallRoot C:\EmailPrint -QueueRoot C:\EmailPrintQueue -DefaultPrinter "Front Office Printer" -SumatraPdfPath "C:\Program Files\SumatraPDF\SumatraPDF.exe" -EveryMinutes 1 -NonInteractive
```

## 4. Manual configuration and validation

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

## 5. Cloud flow design

Create an automated cloud flow:

1. Trigger: **When a new email arrives** for the dedicated mailbox or shared mailbox.
2. Add guard conditions:
   - Optional sender allow-list.
   - Optional subject keyword or category filter.
   - Optional attachment-required check.
3. Compose a unique `JobId`, for example:
   - received timestamp formatted as `yyyyMMdd-HHmmss`
   - message id hash or short GUID
4. Create folder: `EmailPrintQueue/incoming/<JobId>`.
5. Create folder: `EmailPrintQueue/incoming/<JobId>/attachments`.
6. Create `job.json` containing metadata such as sender, subject, received time, message id, and attachment count.
7. Create `body.txt` from the email body if email-body printing is required.
8. For each attachment, create a file under `attachments` using the attachment name.
9. Create `.ready` as the final file in the job folder.
10. Move the email to a mailbox folder such as `Queued for Print` or mark it with a category.

The `.ready` marker is important because OneDrive/SharePoint sync can expose a folder before all files are present. The local worker ignores folders until `.ready` exists.

## 6. Recommended Windows Task Scheduler pattern

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

## 7. Optional Power Automate Desktop pattern

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

## 8. File type policy

Start with PDFs only if possible. Add other extensions only after testing them on the print PC.

Recommended initial policy:

- `.pdf`: supported with SumatraPDF.
- `.txt`: supported with Notepad for simple text.
- Office files: convert to PDF before printing, or add a controlled LibreOffice/Microsoft Office conversion process later.
- Images: add only after testing a dedicated image-print command.
- ZIP files: do not auto-print; route to failed/manual review.

## 9. Support process

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
