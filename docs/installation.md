# AD Account Lockout Monitor --- Installation Guide

**Version:** 1.0.0\
**Author:** Madhushanka Lakmal\
**Platform:** Windows / Windows PowerShell 5.1\
**Monitored Event:** Security Event ID 4740

## 1. Overview

This guide describes installation and production deployment of the AD
Account Lockout Monitor.

The recommended production location is:

``` text
C:\ProgramData\ADLockoutMonitor\
```

The monitor checks configured Active Directory Domain Controllers for
Security Event ID **4740 (A user account was locked out)**, maintains
processing state, writes logs, and provides notifications.

## 2. Requirements

-   Windows 10 or later, or supported Windows Server
-   Windows PowerShell 5.1
-   Network/DNS connectivity to the configured Domain Controllers
-   Permission to query the Security event log remotely
-   RPC/remote event-log connectivity between the monitoring system and
    Domain Controllers

Check PowerShell:

``` powershell
$PSVersionTable.PSVersion
```

Test Event ID 4740 access:

``` powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 5
```

Replace example hostnames with the target environment's Domain
Controllers.

## 3. GitHub Repository Structure

Recommended public repository:

``` text
AD-Account-Lockout-Monitor/
│
├── README.md
├── LICENSE
├── .gitignore
│
├── scripts/
│   └── AD-LockoutMonitor.ps1
│
├── config/
│   └── config.example.json
│
├── docs/
│   ├── installation.md
│   ├── configuration.md
│   └── troubleshooting.md
│
└── screenshots/
```

Do **not** commit production `config.json`, `state.json`, logs, or
credentials.

## 4. Production Directory

Create the installation directory:

``` powershell
New-Item -ItemType Directory `
    -Path "C:\ProgramData\ADLockoutMonitor" `
    -Force

New-Item -ItemType Directory `
    -Path "C:\ProgramData\ADLockoutMonitor\Logs" `
    -Force
```

Copy the script:

``` powershell
Copy-Item `
    ".\scripts\AD-LockoutMonitor.ps1" `
    "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1" `
    -Force
```

## 5. Production Configuration

Create:

``` text
C:\ProgramData\ADLockoutMonitor\config.json
```

Example:

``` json
{
    "StateFile": "C:\\ProgramData\\ADLockoutMonitor\\state.json",
    "LogDirectory": "C:\\ProgramData\\ADLockoutMonitor\\Logs",
    "EventId": 4740,
    "CheckIntervalSeconds": 30,
    "RediscoverDCsEveryMinutes": 30,
    "AutoDiscoverDomainControllers": false,
    "DomainControllers": [
        "DC01.example.com",
        "DC02.example.com"
    ],
    "Notification": {
        "Enabled": true,
        "WindowsEventLog": true
    }
}
```

The example hostnames are placeholders. Use the actual Domain
Controllers in the deployment environment.

For the current v1.0.0 design, explicit Domain Controller configuration
is recommended:

``` json
"AutoDiscoverDomainControllers": false
```

and:

``` json
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com"
]
```

The public repository should contain only `config.example.json`, not a
real production `config.json`.

## 6. Test Domain Controller Connectivity

For each configured Domain Controller:

``` powershell
Test-NetConnection "DC01.example.com"
```

Then test Event ID 4740:

``` powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 5
```

Repeat for each configured Domain Controller.

If there are no matching events, an empty result is different from a
connectivity or permission failure.

## 7. Manual Installation Test

Change to the production directory:

``` powershell
Set-Location "C:\ProgramData\ADLockoutMonitor"
```

Run:

``` powershell
.\AD-LockoutMonitor.ps1
```

Verify that the monitor loads configuration, checks the configured
Domain Controllers, logs its activity, and continues polling.

Press `Ctrl+C` to stop a manual test.

## 8. First-Run State Behavior

When a Domain Controller has no previous state, the monitor initializes
its state from the latest available Event ID 4740.

Historical lockouts are not intended to generate alerts during this
initial baseline.

After initialization, the monitor processes events with a Record ID
newer than the stored state.

Runtime state is stored in:

``` text
C:\ProgramData\ADLockoutMonitor\state.json
```

## 9. Runtime Files

A production installation can contain:

``` text
C:\ProgramData\ADLockoutMonitor\
│
├── AD-LockoutMonitor.ps1
├── config.json
├── state.json
│
└── Logs\
    └── AD-LockoutMonitor.log
```

The script manages runtime state/logging. These files should not be
committed to GitHub.

If SMTP credentials are configured, credential storage such as:

``` text
smtp-credential.xml
```

must also remain outside the repository.

## 10. Scheduled Task

Recommended current deployment:

``` text
Task Name:          AD Lockout Monitor
Run As:             SYSTEM
Privileges:         Highest privileges
Start:              07:00
Execution window:   07:00 - 19:00
Restart attempts:   3
Restart interval:   1 minute
```

Action:

``` text
powershell.exe
```

Arguments:

``` text
-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1"
```

Configure this through Task Scheduler.

## 11. Start and Verify the Task

Start:

``` powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

Check state:

``` powershell
Get-ScheduledTask -TaskName "AD Lockout Monitor" |
    Select-Object TaskName, State
```

Get execution information:

``` powershell
Get-ScheduledTaskInfo -TaskName "AD Lockout Monitor"
```

Check the monitor process:

``` powershell
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    } |
    Select-Object ProcessId, CommandLine
```

## 12. Verify Logs

Check the latest entries:

``` powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Tail 50
```

A detected lockout should contain:

``` text
LOCKOUT DETECTED
```

with relevant user, domain, caller, Domain Controller, time, and Event
Record ID information.

## 13. Test a New Lockout

Use an approved test account.

After generating a controlled account lockout, check:

``` powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" `
    -Tail 30
```

Then inspect:

``` powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\state.json"
```

The corresponding Domain Controller Record ID should advance.

Allow another polling cycle and confirm the same Record ID is not
alerted again.

## 14. Windows Notifications

The current v1.0.0 implementation uses Windows Forms notification
functionality.

It also supports writing lockout notifications to the Windows
Application Event Log using the source:

``` text
AD-LockoutMonitor
```

Verify Application events:

``` powershell
Get-WinEvent -FilterHashtable @{
    LogName = "Application"
} -MaxEvents 20 |
Where-Object {
    $_.ProviderName -eq "AD-LockoutMonitor"
}
```

## 15. Troubleshooting

### Script not found

``` powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1"
```

Expected:

``` text
True
```

### Configuration problem

``` powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\config.json"
Get-Content "C:\ProgramData\ADLockoutMonitor\config.json"
```

Check JSON syntax and Domain Controller names.

### Remote Event Log query fails

Test:

``` powershell
Test-NetConnection "DC01.example.com"
```

Then:

``` powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 5
```

Check DNS, network connectivity, RPC, Windows Firewall, permissions, and
domain connectivity.

### No new lockout detected

Verify that Event ID 4740 exists:

``` powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 10
```

Then inspect `state.json`. The monitor processes events newer than the
saved Record ID.

### Duplicate alerts

Inspect:

``` powershell
Get-Content "C:\ProgramData\ADLockoutMonitor\state.json"
```

The stored Record ID should advance after processing a new event.

Do not delete `state.json` during normal operation unless
reinitialization is intentional.

## 16. Updating an Existing Installation

When installing a newer script version:

1.  Stop the Scheduled Task.
2.  Back up the current script.
3.  Copy the new script.
4.  Keep the existing production `config.json`.
5.  Keep `state.json` unless the release specifically requires a state
    reset.
6.  Perform a manual validation.
7.  Start the Scheduled Task.
8.  Review the monitoring log.
9.  Perform a controlled test when required.

Example:

``` powershell
Stop-ScheduledTask -TaskName "AD Lockout Monitor"
```

After updating:

``` powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

## 17. Rollback

If a new script version causes a problem:

``` powershell
Stop-ScheduledTask -TaskName "AD Lockout Monitor"
```

Restore the previous known-good script, then:

``` powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

Verify:

``` powershell
Get-ScheduledTaskInfo -TaskName "AD Lockout Monitor"
```

## 18. Production Security Checklist

Before production deployment:

-   [ ] Script copied to the intended directory
-   [ ] Production `config.json` created locally
-   [ ] Real Domain Controllers configured
-   [ ] Remote Event ID 4740 query tested
-   [ ] DNS tested
-   [ ] Network/RPC connectivity tested
-   [ ] Required permissions verified
-   [ ] Runtime directories accessible
-   [ ] SMTP credentials protected if used
-   [ ] Production configuration excluded from Git
-   [ ] Logs excluded from Git
-   [ ] `state.json` excluded from Git
-   [ ] Scheduled Task configured
-   [ ] Manual test completed
-   [ ] Controlled lockout test completed
-   [ ] Duplicate prevention verified

## 19. GitHub Security Checklist

Never commit:

``` text
config.json
state.json
*.log
Logs/
smtp-credential.xml
*.secret
*.key
*.pem
*.pfx
*.p12
```

Before pushing:

``` powershell
git status
git diff
```

Search the repository for environment-specific information before a
public push.

Example first-pass search:

``` powershell
Get-ChildItem -Recurse -File |
    Select-String -Pattern `
    "example.com|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168|smtp"
```

Also review the script manually for real hostnames, usernames, email
addresses, internal URLs, and other organization-specific information.

## 20. Installation Flow

``` text
Clone / download repository
          |
          v
Review requirements
          |
          v
Create C:\ProgramData\ADLockoutMonitor
          |
          v
Copy AD-LockoutMonitor.ps1
          |
          v
Create production config.json
          |
          v
Configure Domain Controllers
          |
          v
Test Get-WinEvent access
          |
          v
Run monitor manually
          |
          v
Verify logs / state / notifications
          |
          v
Create Scheduled Task
          |
          v
Start Scheduled Task
          |
          v
Perform controlled lockout test
          |
          v
Production monitoring
```

## 21. Separation Between GitHub and Production

The GitHub repository contains the reusable software and documentation.

The production installation contains environment-specific configuration
and runtime data.

``` text
GitHub
  |
  +-- PowerShell script
  +-- Documentation
  +-- Example configuration
  |
  X-- Real domain names
  X-- Real credentials
  X-- Production logs
  X-- Runtime state
```

This separation allows the project to be shared without exposing private
infrastructure information.

------------------------------------------------------------------------

**AD Account Lockout Monitor v1.0.0**\
**Author:** Madhushanka Lakmal
