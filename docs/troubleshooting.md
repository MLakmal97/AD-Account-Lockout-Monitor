# Troubleshooting Guide

## AD Account Lockout Monitor

**Version:** 1.0.0  
**Author:** Madhushanka Lakmal  
**Platform:** Windows PowerShell 5.1  
**Primary Event:** Security Event ID 4740

---

## 1. Purpose

This guide covers common installation, runtime, Active Directory, Event ID 4740, state tracking, notification, and Scheduled Task problems for AD Account Lockout Monitor v1.0.0.

The procedures reflect issues encountered while developing and testing the monitor.

---

## 2. Basic Health Check

Check the script:

```powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1"
```

Expected:

```text
True
```

Check configuration:

```powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\config.json"
```

Check state:

```powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\state.json"
```

The state file may not exist before first initialization.

Check logs:

```powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\Logs"
```

---

## 3. Check the Scheduled Task

```powershell
Get-ScheduledTask -TaskName "AD Lockout Monitor" |
    Select-Object TaskName, State
```

Detailed information:

```powershell
Get-ScheduledTaskInfo -TaskName "AD Lockout Monitor"
```

Check the actual monitor process:

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    } |
    Select-Object ProcessId, CommandLine
```

A task can show a valid Task Scheduler state while the script itself has stopped, so check the process and log as well.

---

## 4. Manually Run the Monitor

Stop the Scheduled Task before starting a manual copy of the monitor:

```powershell
Stop-ScheduledTask -TaskName "AD Lockout Monitor"
```

Then:

```powershell
Set-Location "C:\ProgramData\ADLockoutMonitor"
.\AD-LockoutMonitor.ps1
```

Manual execution is useful because script errors appear directly in the PowerShell console.

Stop the manual test with:

```text
Ctrl+C
```

Then restart the Scheduled Task:

```powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

---

## 5. Domain Controller Connectivity Problems

Test network connectivity:

```powershell
Test-NetConnection "DC01.example.com"
```

Test Security Event ID 4740:

```powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 5
```

Check:

- DNS resolution
- Network connectivity
- RPC connectivity
- Windows Firewall
- Remote Event Log access
- Security Event Log permissions
- Domain connectivity

If `Get-WinEvent` works manually against the same Domain Controller, the remote event query path is functioning.

---

## 6. No Matching Events Is Not Necessarily an Error

During development, `Get-WinEvent` could produce:

```text
No events were found that match the specified selection criteria.
```

This occurs when no matching events are returned.

The monitor was changed to handle an empty event collection as a normal monitoring condition.

The current approach uses an array and suppresses the empty-result error:

```powershell
$Events =
    @(
        Get-WinEvent `
            -ComputerName $DomainController `
            -FilterHashtable @{
                LogName = "Security"
                Id      = $EventId
            } `
            -MaxEvents 100 `
            -ErrorAction SilentlyContinue
    )
```

Then:

```powershell
if ($Events.Count -eq 0) {
    ...
}
```

This prevents a normal empty query result from becoming a monitoring error.

---

## 7. "No Event ID 4740 Records" vs "No New Events"

A Domain Controller can contain historical Event ID 4740 records while having no new lockouts.

### First-run condition

When a Domain Controller has no previous state and no Event 4740 records:

```text
DC01.example.com has no Event ID 4740 records.
```

### Normal monitoring condition

When the Domain Controller has already been initialized:

```text
No new Event ID 4740 events found on DC01.example.com. Last Record ID: 123456.
```

These are different conditions.

---

## 8. Unwanted Domain Controllers Are Discovered

If automatic discovery returns Domain Controllers outside the intended scope, use an explicit list:

```json
"AutoDiscoverDomainControllers": false
```

and:

```json
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com"
]
```

With automatic discovery disabled, the explicit list controls the monitoring scope.

---

## 9. Event ID 4740 Field Interpretation

The Event ID 4740 XML structure encountered during testing contained fields including:

```text
TargetUserName
TargetDomainName
TargetSid
SubjectUserSid
SubjectUserName
SubjectDomainName
```

In the tested environment:

```text
TargetUserName    = locked user
TargetDomainName  = caller computer recorded by the event
SubjectUserName   = Domain Controller computer account
SubjectDomainName = AD domain
```

Therefore the monitor uses:

```text
TargetUserName
    ↓
Locked account

TargetDomainName
    ↓
Caller computer recorded by Event 4740

SubjectDomainName
    ↓
AD domain
```

Do not assume `TargetDomainName` is the AD domain for this event format.

---

## 10. Missing `SubjectDomainName`

An earlier parser expected a property that was not always available.

The parser was changed to process the event XML as a dictionary of event fields.

The current implementation also has a fallback when the domain value is empty:

```powershell
if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = "MCBLK"
}
```

For a reusable public release, environment-specific fallback values should ideally become configurable or dynamically determined in a future version.

---

## 11. Lockout Notification Parameter Error

An earlier version had a mismatch between the parameters expected by `Show-LockoutNotification` and the parameters supplied by `Process-DomainController`.

The call must include lockout time:

```powershell
Show-LockoutNotification `
    -UserName $Username `
    -Domain $Domain `
    -CallerComputer $CallerComputer `
    -DomainController $DomainController `
    -LockoutTime $LockoutTime `
    -RecordId $RecordId
```

If a parameter mismatch occurs, inspect the function definition and compare its parameter list with the call site.

---

## 12. Windows Toast Notification Errors

The first notification implementation attempted Windows Runtime toast notification types such as:

```text
Windows.Data.Xml.Dom.XmlDocument
Windows.UI.Notifications.ToastNotification
Windows.UI.Notifications.ToastNotificationManager
```

Those types were unavailable in the tested PowerShell execution context.

The v1.0.0 implementation uses Windows Forms notification functionality:

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
```

and a `NotifyIcon` balloon notification.

---

## 13. State File Problems

The monitor uses:

```text
C:\ProgramData\ADLockoutMonitor\state.json
```

to remember the last processed Event Record ID for each Domain Controller.

During development, state-file replacement/sharing problems were encountered.

If state saving fails, check:

```powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\state.json"
```

Check directory permissions:

```powershell
Get-Acl "C:\ProgramData\ADLockoutMonitor"
```

Also inspect the monitoring log for messages such as:

```text
State saved successfully.
```

or:

```text
state update FAILED
```

---

## 14. State Record ID Does Not Advance

The monitor processes only events where:

```text
Current Record ID > Last Record ID
```

Check the state:

```powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\state.json"
```

Check the latest Event 4740:

```powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 1 |
    Select-Object TimeCreated, RecordId
```

Compare the latest Record ID with the stored Record ID.

If the latest Record ID is not greater, the event has already been processed.

---

## 15. Historical Events Are Alerting After Startup

The monitor baselines a Domain Controller when it has no previous state.

The initialization process:

```text
First run
   ↓
No previous DC state
   ↓
Read latest Event 4740
   ↓
Save latest Record ID
   ↓
Do not alert historical events
   ↓
Monitor new events
```

If historical events are unexpectedly alerting, inspect `state.json` and the initialization logic.

Do not delete the state file unless reinitialization is intentional.

---

## 16. Duplicate Lockout Alerts

Duplicate prevention is based on Event Record ID.

Check the log for:

```text
state updated to Record ID XXXXX.
```

Then check `state.json`.

If duplicates appear:

1. Stop the monitor.
2. Inspect `state.json`.
3. Check whether state updates succeeded.
4. Check whether more than one monitor process is running.
5. Restart only one monitor instance.

Check processes:

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    } |
    Select-Object ProcessId, CommandLine
```

---

## 17. Multiple Monitor Processes

Running the script manually while the Scheduled Task is running can create two monitor instances.

Check:

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    } |
    Select-Object ProcessId, CommandLine
```

Before manual troubleshooting:

```powershell
Stop-ScheduledTask -TaskName "AD Lockout Monitor"
```

After testing:

```powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

---

## 18. Scheduled Task Is Running but No Alerts

Check task state:

```powershell
Get-ScheduledTask -TaskName "AD Lockout Monitor" |
    Select-Object TaskName, State
```

Check execution information:

```powershell
Get-ScheduledTaskInfo -TaskName "AD Lockout Monitor"
```

Check the process:

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    } |
    Select-Object ProcessId, CommandLine
```

Check the log:

```powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Tail 50
```

Then test the Domain Controller directly using `Get-WinEvent`.

---

## 19. Scheduled Task Result Code Looks Unusual

Check:

```powershell
Get-ScheduledTaskInfo -TaskName "AD Lockout Monitor" |
    Format-List *
```

Do not diagnose the monitor solely from `LastTaskResult`.

Also verify:

- Task state
- Actual PowerShell process
- Monitor log
- Domain Controller connectivity
- Script errors

A running process with continuously updating logs provides useful runtime evidence.

---

## 20. Script Execution Policy Error

Check current policies:

```powershell
Get-ExecutionPolicy -List
```

The configured Scheduled Task action uses:

```text
-NoProfile -ExecutionPolicy Bypass
```

The action is:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1"
```

Follow the organization's security policy before changing execution policy settings.

---

## 21. Script Syntax Check

Before deploying a modified script, perform a parser check:

```powershell
$Errors = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1",
    [ref]$null,
    [ref]$Errors
)

$Errors
```

If parser errors are returned, correct them before starting the monitor.

---

## 22. Log Investigation

Show the latest 100 lines:

```powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Tail 100
```

Search for errors:

```powershell
Select-String `
    -Path "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Pattern "\[ERROR\]"
```

Search for lockouts:

```powershell
Select-String `
    -Path "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Pattern "LOCKOUT DETECTED"
```

Search for state updates:

```powershell
Select-String `
    -Path "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Pattern "state updated"
```

---

## 23. Controlled Test Reset

Stop the monitor:

```powershell
Stop-ScheduledTask -TaskName "AD Lockout Monitor"
```

Back up the state file:

```powershell
Copy-Item `
    "C:\ProgramData\ADLockoutMonitor\state.json" `
    "C:\ProgramData\ADLockoutMonitor\state.json.backup" `
    -Force `
    -ErrorAction SilentlyContinue
```

Only when intentionally reinitializing:

```powershell
Remove-Item `
    "C:\ProgramData\ADLockoutMonitor\state.json" `
    -Force `
    -ErrorAction SilentlyContinue
```

Clear test logs if appropriate:

```powershell
Remove-Item `
    "C:\ProgramData\ADLockoutMonitor\Logs\*" `
    -Force `
    -ErrorAction SilentlyContinue
```

Start again:

```powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

**Warning:** Do not reset `state.json` casually in production. Removing it causes the monitor to establish a new baseline.

---

## 24. Recommended Troubleshooting Order

When the monitor does not work, troubleshoot from the outside in:

```text
1. Scheduled Task
       ↓
2. PowerShell process
       ↓
3. Script startup
       ↓
4. Configuration
       ↓
5. Domain Controller connectivity
       ↓
6. Get-WinEvent
       ↓
7. Event 4740 parsing
       ↓
8. State tracking
       ↓
9. Notification
       ↓
10. Scheduled monitoring
```

This avoids changing the script before confirming the underlying infrastructure.

---

## 25. Diagnostic Command Set

```powershell
# Task
Get-ScheduledTask -TaskName "AD Lockout Monitor" |
    Select-Object TaskName, State

# Task information
Get-ScheduledTaskInfo -TaskName "AD Lockout Monitor"

# Monitor process
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    } |
    Select-Object ProcessId, CommandLine

# Configuration
Get-Content "C:\ProgramData\ADLockoutMonitor\config.json"

# State
Get-Content "C:\ProgramData\ADLockoutMonitor\state.json"

# Recent logs
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Tail 50
```

---

## 26. Production Incident Checklist

- [ ] Check Scheduled Task state.
- [ ] Check actual monitor process.
- [ ] Check latest monitor log.
- [ ] Check for `[ERROR]` entries.
- [ ] Verify Domain Controller connectivity.
- [ ] Query Event ID 4740 directly.
- [ ] Compare latest Event Record ID with `state.json`.
- [ ] Verify only one monitor instance is running.
- [ ] Check notification separately from event detection.
- [ ] Preserve logs before clearing anything.
- [ ] Avoid deleting `state.json` unless reinitialization is intentional.
- [ ] Record the issue time.
- [ ] Record the affected Domain Controller.
- [ ] Record the Event Record ID when available.

---

## 27. Known v1.0.0 Limitations

Version 1.0.0 focuses on Event ID 4740.

It does not yet provide complete authentication-event correlation with:

```text
4771 - Kerberos pre-authentication failure
4776 - NTLM authentication
4625 - Failed logon
```

Therefore, Event ID 4740 can identify the locked account and event-related caller information, but deeper root-cause analysis may require additional Security event correlation.

Potential future improvements:

- Event 4740 + 4771 correlation
- Event 4740 + 4776 correlation
- Event 4740 + 4625 correlation
- Source classification
- Cached credential detection
- Mapped drive investigation
- Scheduled task/service investigation
- Outlook/Exchange authentication investigation
- Additional notification channels

---

## 28. Safe GitHub Troubleshooting Practices

Never upload production troubleshooting data containing:

```text
Real usernames
Real Domain Controller names
Internal domain names
Internal IP addresses
Email addresses
SMTP information
Credentials
Production event logs
Production state files
```

Before committing:

```powershell
git status
```

Review changes:

```powershell
git diff
```

Search the repository for sensitive values before pushing.

Use placeholders in public documentation:

```text
DC01.example.com
DC02.example.com
user@example.com
```

rather than real organization information.

---

## 29. Quick Reference

| Problem | First Check |
|---|---|
| Script will not start | Run it manually |
| Task not running | `Get-ScheduledTask` |
| No lockout detected | Query Event ID 4740 directly |
| DC unavailable | `Test-NetConnection` |
| No matching events | Check whether Event 4740 exists |
| Historical events alert | Check `state.json` initialization |
| Duplicate alerts | Check Record ID/state and running processes |
| State not updating | Check `state.json` permissions and log |
| Notification fails | Test event detection separately |
| Toast notification fails | v1.0.0 uses Windows Forms |
| Multiple alerts | Check for multiple monitor processes |
| Production config exposed | Remove from Git and review Git history before public push |

---

**AD Account Lockout Monitor v1.0.0**  
**Author:** Madhushanka Lakmal
