# AD Account Lockout Monitor

A lightweight PowerShell-based Active Directory account lockout monitoring tool for Windows environments.

The tool monitors **Event ID 4740 (A user account was locked out)** on configured Active Directory Domain Controllers and provides visibility through console output, Windows desktop notifications, Windows Application Event Log entries, and persistent log files.

> **Version:** 1.0.0  
> **Author:** Madhushanka Lakmal  
> **Role:** IT Operations Officer  
> **Platform:** Windows PowerShell 5.1  
> **License:** MIT

---

## Features

- Monitors Active Directory **Event ID 4740**
- Supports multiple Domain Controllers
- Explicit Domain Controller configuration
- Optional automatic Domain Controller discovery
- Tracks the last processed Event Record ID
- Prevents duplicate alerts
- Does not alert on historical lockout events during first initialization
- Windows desktop balloon notifications
- Windows Application Event Log integration
- Persistent operational logging
- Automatic state persistence
- Handles temporary Domain Controller connectivity failures
- Designed for Windows PowerShell 5.1
- Suitable for Scheduled Task deployment
- Keeps production configuration and runtime data outside the public repository

---

## How It Works

```text
                  +--------------------------+
                  | Active Directory Domain  |
                  +------------+-------------+
                               |
                     Event ID 4740
                               |
              +----------------v----------------+
              |     AD Lockout Monitor          |
              |     PowerShell 5.1              |
              +----------------+-----------------+
                               |
              +----------------+----------------+
              |                |                |
              v                v                v
       Windows Popup      Event Log          Log File
       Notification       Application        Persistent
              |                |                |
              +----------------+----------------+
                               |
                         State Tracking
                          state.json
```

The monitor periodically queries configured Domain Controllers and processes only events whose `RecordId` is newer than the previously processed value.

---

## Event ID 4740

The tool monitors:

```text
Security Log
Event ID: 4740
Description: A user account was locked out
```

The monitor extracts information such as:

| Field | Purpose |
|---|---|
| TargetUserName | Locked user account |
| TargetDomainName | Caller/computer information in the observed environment |
| SubjectDomainName | Active Directory domain |
| SubjectUserName | Account that generated the event context |
| RecordId | Windows Event Log record identifier |
| TimeCreated | Lockout event time |
| DomainController | DC where the event was detected |

### Environment-specific behavior

In the development environment, Event ID 4740 was observed with:

```text
TargetUserName     = locked user
TargetDomainName   = caller computer name
SubjectDomainName  = MCBLK
SubjectUserName    = Domain Controller computer account
```

Therefore, the script uses:

```text
TargetUserName     -> Locked User
TargetDomainName   -> Caller Computer
SubjectDomainName  -> AD Domain
```

Event field behavior can vary by environment, so verify the actual event XML in your own domain before relying on a field for automation.

---

## Repository Structure

Recommended public repository structure:

```text
AD-Account-Lockout-Monitor/
|
+-- README.md
+-- LICENSE
+-- .gitignore
|
+-- scripts/
|   +-- AD-LockoutMonitor.ps1
|
+-- config/
|   +-- config.example.json
|
+-- docs/
|   +-- installation.md
|   +-- configuration.md
|   +-- troubleshooting.md
|
+-- screenshots/
    +-- .gitkeep
```

---

# Installation

## Requirements

- Windows 10 / Windows 11 or Windows Server
- Windows PowerShell 5.1
- Network connectivity to monitored Domain Controllers
- Permission to query the Security event log on monitored DCs
- Permission to create/write the configured log and state directories
- Administrator privileges for production installation and Scheduled Task configuration

---

## Production Directory

Recommended production location:

```text
C:\ProgramData\ADLockoutMonitor\
```

Example:

```text
C:\ProgramData\ADLockoutMonitor\
|
+-- AD-LockoutMonitor.ps1
+-- config.json
+-- state.json
+-- smtp-credential.xml
|
+-- Logs\
    +-- AD-LockoutMonitor.log
```

### Runtime files

| File / Directory | Purpose | Commit to GitHub? |
|---|---|---|
| `AD-LockoutMonitor.ps1` | Main script | Yes |
| `config.json` | Production configuration | **No** |
| `config.example.json` | Safe configuration template | Yes |
| `state.json` | Runtime event state | **No** |
| `Logs\` | Runtime logs | **No** |
| `AD-LockoutMonitor.log` | Operational log | **No** |
| `smtp-credential.xml` | Stored SMTP credential | **Never** |

---

# Configuration

A safe example configuration should be stored in:

```text
config/config.example.json
```

Example:

```json
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

Keep the real production configuration outside GitHub:

```text
C:\ProgramData\ADLockoutMonitor\config.json
```

---

# Domain Controller Monitoring

## Explicit DC List

Recommended when you want strict control over which Domain Controllers are monitored:

```json
"AutoDiscoverDomainControllers": false,
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com"
]
```

The monitor will use only the configured DCs.

## Automatic Discovery

Automatic discovery can be enabled when appropriate:

```json
"AutoDiscoverDomainControllers": true
```

For environments containing multiple geographic sites, forests, domains, or other infrastructure, review the discovered list carefully before using automatic discovery in production.

---

# First Run and State Tracking

The monitor stores the latest processed Event Record ID for each Domain Controller in:

```text
C:\ProgramData\ADLockoutMonitor\state.json
```

Example:

```json
{
    "DCs": {
        "DC01.example.com": 123456,
        "DC02.example.com": 234567
    }
}
```

## First Run Behavior

When a Domain Controller has no previous state:

1. The script searches for the latest Event ID 4740.
2. The latest `RecordId` is stored.
3. Existing historical events are not alerted.
4. Future events with a higher `RecordId` are processed.

This prevents a large number of alerts when the monitor is first installed.

---

# Monitoring Loop

The current configuration checks monitored Domain Controllers every:

```text
30 seconds
```

Configured with:

```json
"CheckIntervalSeconds": 30
```

Processing logic:

```text
Stored RecordId
       |
       v
Query Event ID 4740
       |
       v
RecordId > Stored?
    |        |
   Yes       No
    |        |
    v        v
Process    No Alert
 Event
    |
    v
Save State
```

---

# Notifications

The current v1.0.0 implementation supports:

### Console output

The monitor writes operational information to the PowerShell console.

Example:

```text
LOCKOUT DETECTED | User=user01 | Domain=MCBLK |
Caller=CLIENT-001 | DC=DC01.example.com |
Time=2026-09-24 10:15:30 | RecordId=123456
```

### Windows desktop notification

The monitor uses Windows Forms `NotifyIcon` balloon notifications.

Required assemblies:

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
```

### Windows Application Event Log

The monitor can write lockout information to the Windows Application Event Log.

Configured source:

```text
AD-LockoutMonitor
```

### Persistent application log

Operational messages are written to:

```text
C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log
```

---

# Scheduled Task

For operational monitoring, the script can be executed through Windows Task Scheduler.

Recommended configuration:

```text
Task Name:
AD Lockout Monitor

Run As:
SYSTEM

Run with highest privileges:
Enabled

Trigger:
Daily at 07:00

Execution Window:
07:00-19:00
```

Action:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1"
```

The current production setup uses the Scheduled Task execution window to control when the monitor runs.

---

# Manual Testing

Run PowerShell as Administrator:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\ADLockoutMonitor\AD-LockoutMonitor.ps1"
```

Check the log:

```powershell
Get-Content "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" -Tail 50
```

Check the state:

```powershell
Get-Content "C:\ProgramData\ADLockoutMonitor\state.json"
```

---

# Domain Controller Connectivity Test

Test Event Log access before troubleshooting the monitor itself:

```powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 5
```

Repeat for every monitored Domain Controller.

If this command cannot retrieve events, troubleshoot connectivity and permissions before changing the monitor script.

---

# Troubleshooting

## No new lockout alerts

Check:

```powershell
Get-Content "C:\ProgramData\ADLockoutMonitor\Logs\AD-LockoutMonitor.log" -Tail 100
```

Then test the DC directly:

```powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 10
```

## RPC Server Unavailable

Verify:

```powershell
Test-NetConnection DC01.example.com -Port 135
```

Also verify DNS:

```powershell
Resolve-DnsName DC01.example.com
```

Check Windows Firewall, RPC connectivity, network routing, and permissions.

## Historical events are alerting

Check:

```text
C:\ProgramData\ADLockoutMonitor\state.json
```

The first initialization is designed to establish a baseline rather than alert on historical events.

## Duplicate alerts

Check whether multiple copies of the script are running:

```powershell
Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -like "*AD-LockoutMonitor.ps1*"
    }
```

Also check Task Scheduler for duplicate tasks.

## State file problems

Check:

```powershell
Test-Path "C:\ProgramData\ADLockoutMonitor\state.json"
```

Check permissions:

```powershell
Get-Acl "C:\ProgramData\ADLockoutMonitor"
```

Do not delete `state.json` during normal operation unless you intentionally want to re-baseline the monitor.

---

# Security Considerations

This project is intended for infrastructure and system administration use.

## Never commit

Do not commit:

```text
config.json
state.json
*.log
smtp-credential.xml
*.key
*.pem
*.pfx
*.p12
.env
```

The repository includes `.gitignore` rules intended to prevent common sensitive files from being committed.

## Production data

Do not publish:

- Internal Domain Controller hostnames
- Internal IP addresses
- User account names
- Security event exports
- Internal SMTP server details
- Credentials
- Certificates/private keys
- Production log files
- Production state files
- Other confidential infrastructure information

Use sanitized examples in public documentation.

---

# GitHub Workflow

After repository setup:

```powershell
git status
git diff
git add .
git commit -m "Describe the change"
git push
```

Recommended workflow:

```text
Edit
  |
  v
Test
  |
  v
git status
  |
  v
git diff
  |
  v
git add .
  |
  v
git commit
  |
  v
git push
```

### Example commit messages

```text
Improve lockout event logging
```

```text
Improve DC connectivity handling
```

```text
Add working hours protection
```

```text
Improve Windows notifications
```

```text
Add configuration documentation
```

---

# Versioning

The project currently uses:

```text
v1.0.0
```

Create a release tag with:

```powershell
git tag -a v1.0.0 -m "AD Account Lockout Monitor v1.0.0"
git push origin v1.0.0
```

Future releases can follow Semantic Versioning:

```text
MAJOR.MINOR.PATCH
```

Examples:

```text
v1.1.0
v1.2.0
v2.0.0
```

---

# Current Limitations - v1.0.0

- Windows PowerShell 5.1 focused
- Windows Forms notification rather than WinRT toast notification
- Configuration is file-based
- Runtime state is stored locally
- No centralized web dashboard
- No database backend
- No REST API
- Email notification is not part of the minimal current configuration
- Scheduled Task is used for operational scheduling
- Monitoring scope is controlled through the configured Domain Controller list when automatic discovery is disabled

---

# Roadmap

## v1.1

- Working-hours protection inside the script
- Improved notification formatting
- Additional event metadata
- Better connectivity status reporting
- More configuration validation
- Improved log rotation

## v1.2

- Optional SMTP alerting
- Alert severity levels
- Alert filtering
- Configurable notification channels
- Better health monitoring

## v2.x

- Windows service architecture
- Centralized management
- Multi-server monitoring
- Web dashboard
- REST API
- Database-backed event history
- Role-based access control
- Reporting and analytics

Future features should be designed without requiring production security data to be sent to an external service unless explicitly configured by the organization.

---

# Documentation

Additional documentation:

```text
docs/
+-- installation.md
+-- configuration.md
+-- troubleshooting.md
```

These documents provide detailed deployment, configuration, and troubleshooting procedures.

---

# Project Goals

The project is intended to demonstrate practical PowerShell automation for:

- Active Directory administration
- Security event monitoring
- Windows infrastructure monitoring
- Event-driven troubleshooting
- Operational alerting
- State management
- Scheduled automation
- Production-oriented scripting
- Git/GitHub workflow

---

# Contributing

Contributions are welcome.

Before submitting changes:

1. Test the script in a non-production environment.
2. Do not include real credentials or production infrastructure information.
3. Do not commit production logs or state files.
4. Follow the existing PowerShell structure.
5. Use clear commit messages.
6. Update documentation when behavior changes.

---

# License

This project is licensed under the MIT License.

See:

```text
LICENSE
```

for the complete license text.

---

## Author

**Madhushanka Lakmal**  
IT Operations Officer  
PowerShell | Windows Server | Active Directory | Infrastructure Automation

---

> This project is provided as an infrastructure automation example. Always test changes in a controlled environment before deploying them to production.
