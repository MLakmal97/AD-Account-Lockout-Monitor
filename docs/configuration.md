# Configuration Guide

## AD Account Lockout Monitor

**Version:** 1.0.0  
**Author:** Madhushanka Lakmal  
**Configuration file:** `config.json`

---

## 1. Overview

The AD Account Lockout Monitor uses a JSON configuration file to define monitoring behavior, runtime paths, Domain Controllers, and notification settings.

The production configuration file is:

```text
C:\ProgramData\ADLockoutMonitor\config.json
```

The public GitHub repository should contain:

```text
config/config.example.json
```

Do **not** publish a production `config.json` containing real infrastructure information.

---

## 2. Configuration File

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

The values above are examples.

Replace the example Domain Controller names with the actual Domain Controllers in the target environment.

---

# 3. Configuration Reference

## 3.1 `StateFile`

Example:

```json
"StateFile": "C:\\ProgramData\\ADLockoutMonitor\\state.json"
```

### Purpose

Defines where the monitor stores its persistent processing state.

The state file allows the monitor to remember the last processed Event Record ID for each monitored Domain Controller.

### Example

```text
C:\ProgramData\ADLockoutMonitor\state.json
```

### Important

Do not commit the production state file to GitHub.

Add the following to `.gitignore`:

```gitignore
state.json
```

---

# 4. `LogDirectory`

Example:

```json
"LogDirectory": "C:\\ProgramData\\ADLockoutMonitor\\Logs"
```

### Purpose

Defines the directory used for monitor log files.

Example:

```text
C:\ProgramData\ADLockoutMonitor\Logs\
```

The monitor writes its operational log to this directory.

### GitHub

Do not publish production logs.

Recommended `.gitignore` entries:

```gitignore
*.log
Logs/
```

---

# 5. `EventId`

Example:

```json
"EventId": 4740
```

### Purpose

Defines the Windows Security Event ID monitored by the application.

The current version monitors:

```text
4740
```

Event ID 4740 represents:

```text
A user account was locked out
```

### Current Version

```text
v1.0.0 → Event ID 4740
```

Future versions may correlate additional Windows Security events.

---

# 6. `CheckIntervalSeconds`

Example:

```json
"CheckIntervalSeconds": 30
```

### Purpose

Defines how frequently the monitor checks the configured Domain Controllers.

With:

```json
"CheckIntervalSeconds": 30
```

the monitor checks approximately every:

```text
30 seconds
```

### Example

```json
"CheckIntervalSeconds": 60
```

would configure approximately one check per minute.

### Considerations

A shorter interval can detect new events sooner but results in more frequent queries.

A longer interval reduces query frequency but can increase the delay before detection.

---

# 7. `RediscoverDCsEveryMinutes`

Example:

```json
"RediscoverDCsEveryMinutes": 30
```

### Purpose

Defines the interval used for Domain Controller rediscovery when automatic discovery is enabled.

Example:

```json
"RediscoverDCsEveryMinutes": 30
```

means the discovery process can refresh its Domain Controller information every 30 minutes.

### Current v1.0.0 deployment

The current production configuration uses:

```json
"AutoDiscoverDomainControllers": false
```

and explicitly defines the Domain Controllers.

Therefore, the explicit list controls the current monitoring scope.

---

# 8. `AutoDiscoverDomainControllers`

Example:

```json
"AutoDiscoverDomainControllers": false
```

### Purpose

Controls whether the monitor automatically discovers Domain Controllers.

### Disabled

```json
"AutoDiscoverDomainControllers": false
```

The monitor uses:

```json
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com"
]
```

### Enabled

```json
"AutoDiscoverDomainControllers": true
```

The monitor can discover Domain Controllers from Active Directory.

### Current recommendation

For a controlled production monitoring scope, the current v1.0.0 configuration uses:

```json
"AutoDiscoverDomainControllers": false
```

This makes the monitoring scope explicit.

---

# 9. `DomainControllers`

Example:

```json
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com"
]
```

### Purpose

Defines the Domain Controllers monitored by the application when automatic discovery is disabled.

### Example

```json
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com"
]
```

### Important

Use fully qualified hostnames where appropriate for the target environment.

Do not publish real internal Domain Controller names in a public repository.

Use placeholders such as:

```text
DC01.example.com
DC02.example.com
```

in `config.example.json`.

---

# 10. Monitoring Multiple Domain Controllers

The monitor supports multiple Domain Controllers.

Example:

```json
"DomainControllers": [
    "DC01.example.com",
    "DC02.example.com",
    "DC03.example.com"
]
```

Each Domain Controller maintains its own processing state.

Conceptually:

```text
                 AD Lockout Monitor
                        |
        +---------------+---------------+
        |               |               |
        v               v               v
      DC01            DC02            DC03
        |               |               |
        v               v               v
     Record ID       Record ID       Record ID
```

This allows the monitor to track events independently for each configured Domain Controller.

---

# 11. `Notification`

The notification configuration is an object containing notification-related settings.

Example:

```json
"Notification": {
    "Enabled": true,
    "WindowsEventLog": true
}
```

---

# 12. `Notification.Enabled`

Example:

```json
"Enabled": true
```

### Purpose

Controls whether lockout notifications are enabled.

### Enabled

```json
"Enabled": true
```

### Disabled

```json
"Enabled": false
```

The exact notification behavior is controlled by the script's notification implementation.

---

# 13. `Notification.WindowsEventLog`

Example:

```json
"WindowsEventLog": true
```

### Purpose

Controls Windows Application Event Log notification support.

When enabled, the monitor can write lockout notifications to the Windows Application Event Log.

The application source used by the current implementation is:

```text
AD-LockoutMonitor
```

---

# 14. Complete Example Configuration

A safe example configuration for GitHub is:

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

Save this public example as:

```text
config/config.example.json
```

---

# 15. Production Configuration Example

A production administrator creates a separate:

```text
C:\ProgramData\ADLockoutMonitor\config.json
```

and replaces the example values with their own environment.

For example:

```json
{
    "StateFile": "C:\\ProgramData\\ADLockoutMonitor\\state.json",
    "LogDirectory": "C:\\ProgramData\\ADLockoutMonitor\\Logs",
    "EventId": 4740,
    "CheckIntervalSeconds": 30,
    "RediscoverDCsEveryMinutes": 30,
    "AutoDiscoverDomainControllers": false,
    "DomainControllers": [
        "REAL-DC01.example.local",
        "REAL-DC02.example.local"
    ],
    "Notification": {
        "Enabled": true,
        "WindowsEventLog": true
    }
}
```

These names are illustrative only.

---

# 16. Production vs GitHub Configuration

Keep the two configurations separate.

### GitHub

```text
config/
└── config.example.json
```

Contains:

```text
DC01.example.com
DC02.example.com
```

### Production

```text
C:\ProgramData\ADLockoutMonitor\
└── config.json
```

Contains the actual environment-specific configuration.

This prevents internal infrastructure details from being published.

---

# 17. Sensitive Configuration

The following information should not be committed to a public repository:

```text
Real Domain Controller names
Internal domain names
Internal IP addresses
SMTP server names
Email addresses
Usernames
Passwords
API keys
Certificates
Private keys
Credential XML files
Production logs
Runtime state
```

Recommended `.gitignore` entries:

```gitignore
config.json
state.json
Logs/
*.log
*credential*.xml
*.secret
*.key
*.pem
*.pfx
*.p12
.env
.env.*
```

---

# 18. SMTP Configuration

If SMTP functionality is enabled in a deployment, keep SMTP-specific settings and credentials environment-specific.

Do not put credentials directly into the PowerShell script.

Do not commit:

```text
smtp-credential.xml
```

or any file containing authentication secrets.

For a public example, use placeholders such as:

```text
smtp.example.com
```

and:

```text
alerts@example.com
```

Do not use real organizational addresses in the example configuration.

---

# 19. Configuration Validation

After creating the production configuration, inspect it:

```powershell
Get-Content `
    "C:\ProgramData\ADLockoutMonitor\config.json"
```

Verify:

- State file path is correct.
- Log directory is correct.
- Event ID is `4740`.
- Check interval is appropriate.
- Domain Controller list is correct.
- Automatic discovery is set as intended.
- Notification settings are correct.

---

# 20. Validate Domain Controllers

For every configured Domain Controller:

```powershell
Test-NetConnection "DC01.example.com"
```

Then:

```powershell
Get-WinEvent `
    -ComputerName "DC01.example.com" `
    -FilterHashtable @{
        LogName = "Security"
        Id      = 4740
    } `
    -MaxEvents 5
```

Repeat for every Domain Controller.

---

# 21. Configuration Change Workflow

When changing `config.json`:

```text
Stop Monitor
     |
     v
Back up config.json
     |
     v
Edit configuration
     |
     v
Validate Domain Controllers
     |
     v
Run manual test
     |
     v
Start Scheduled Task
     |
     v
Check logs
```

Example:

```powershell
Stop-ScheduledTask -TaskName "AD Lockout Monitor"
```

After testing:

```powershell
Start-ScheduledTask -TaskName "AD Lockout Monitor"
```

Verify:

```powershell
Get-ScheduledTask -TaskName "AD Lockout Monitor" |
    Select-Object TaskName, State
```

---

# 22. Configuration Backup

Before changing a production configuration:

```powershell
Copy-Item `
    "C:\ProgramData\ADLockoutMonitor\config.json" `
    "C:\ProgramData\ADLockoutMonitor\config.json.backup" `
    -Force
```

Keep production backups outside the Git repository.

---

# 23. Configuration Security Checklist

Before production use:

- [ ] `config.json` exists.
- [ ] JSON structure is valid.
- [ ] Event ID is `4740`.
- [ ] Domain Controllers are correct.
- [ ] Domain Controller connectivity tested.
- [ ] Security Event Log query tested.
- [ ] State path is correct.
- [ ] Log path is correct.
- [ ] Notification settings reviewed.
- [ ] SMTP credentials are protected if SMTP is used.
- [ ] `config.json` is excluded from Git.
- [ ] Real domain names are not present in `config.example.json`.
- [ ] Credentials and secrets are not stored in source code.

---

# 24. Recommended Repository Files

The configuration-related repository structure should be:

```text
AD-Account-Lockout-Monitor/
│
├── config/
│   └── config.example.json
│
├── scripts/
│   └── AD-LockoutMonitor.ps1
│
└── docs/
    ├── installation.md
    ├── configuration.md
    └── troubleshooting.md
```

The repository provides the example configuration.

The administrator creates the real production configuration locally.

---

## 25. Quick Reference

| Setting | Example | Purpose |
|---|---|---|
| `StateFile` | `C:\ProgramData\ADLockoutMonitor\state.json` | Runtime state |
| `LogDirectory` | `C:\ProgramData\ADLockoutMonitor\Logs` | Log location |
| `EventId` | `4740` | Lockout event |
| `CheckIntervalSeconds` | `30` | Polling interval |
| `RediscoverDCsEveryMinutes` | `30` | DC discovery interval |
| `AutoDiscoverDomainControllers` | `false` | Automatic DC discovery |
| `DomainControllers` | `DC01.example.com` | Monitoring scope |
| `Notification.Enabled` | `true` | Notification setting |
| `Notification.WindowsEventLog` | `true` | Application Event Log notification |

---

**AD Account Lockout Monitor v1.0.0**  
**Author:** Madhushanka Lakmal
