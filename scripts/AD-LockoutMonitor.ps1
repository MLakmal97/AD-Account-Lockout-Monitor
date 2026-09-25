<#
.SYNOPSIS
    Active Directory Account Lockout Monitor

.DESCRIPTION
    Monitors Active Directory Domain Controllers for Event ID 4740
    (User Account Lockout) and provides Windows desktop notifications
    when a new account lockout is detected.

    The script automatically discovers Domain Controllers and monitors
    all discovered DCs for new account lockout events.

.AUTHOR
    Madhushanka Lakmal

.VERSION
    1.0.0

.CREATED
    2026-09-24

.EVENT
    4740 - A user account was locked out

.FEATURES
    - Automatic Domain Controller discovery
    - Multi-DC monitoring
    - Event ID 4740 monitoring
    - Record ID state tracking
    - Windows desktop notifications
    - Persistent logging
    - Automatic DC rediscovery
    - Historical events are not alerted on first initialization

.FILE
    AD-LockoutMonitor.ps1

.NOTES
    Version 1.0.0
    Initial release
#>

# ============================================================
# CONFIGURATION
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseDirectory = "C:\ProgramData\ADLockoutMonitor"
$ConfigFile    = Join-Path $BaseDirectory "config.json"

# ============================================================
# LOAD CONFIGURATION
# ============================================================

if (-not (Test-Path $ConfigFile)) {

    Write-Host ""
    Write-Host "ERROR: Configuration file not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected file:" -ForegroundColor Yellow
    Write-Host $ConfigFile
    Write-Host ""

    exit 1
}

try {

    $Config = Get-Content -Path $ConfigFile -Raw |
              ConvertFrom-Json

}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to read configuration file." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    exit 1
}

# ============================================================
# WINDOWS NOTIFICATION COMPONENTS
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
# CONFIGURATION VARIABLES
# ============================================================

$StateFile = $Config.StateFile

$LogDirectory = $Config.LogDirectory

$EventId = [int]$Config.EventId

$CheckIntervalSeconds =
    [int]$Config.CheckIntervalSeconds

$RediscoverDCsEveryMinutes =
    [int]$Config.RediscoverDCsEveryMinutes

$AutoDiscover =
    [bool]$Config.AutoDiscoverDomainControllers

$NotificationEnabled =
    [bool]$Config.Notification.Enabled

# ============================================================
# CREATE REQUIRED DIRECTORIES
# ============================================================

if (-not (Test-Path $BaseDirectory)) {

    New-Item `
        -Path $BaseDirectory `
        -ItemType Directory `
        -Force |
        Out-Null
}

if (-not (Test-Path $LogDirectory)) {

    New-Item `
        -Path $LogDirectory `
        -ItemType Directory `
        -Force |
        Out-Null
}

# ============================================================
# LOG FILE
# ============================================================

$LogFile = Join-Path `
    $LogDirectory `
    "AD-LockoutMonitor.log"

# ============================================================
# LOGGING FUNCTION
# ============================================================

function Write-MonitorLog
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Validateset(
            "INFO",
            "WARNING",
            "ERROR",
            "ALERT"
        )]
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $LogEntry = "$Timestamp [$Level] $Message"

    # --------------------------------------------------------
    # Console output
    # --------------------------------------------------------

    switch ($Level)
    {
        "INFO" 
        {
            Write-Host $LogEntry -ForegroundColor Gray
        }
        "WARNING" 
        {
            Write-Host $LogEntry -ForegroundColor Yellow
        }
        "ERROR" 
        {
            Write-Host $LogEntry -ForegroundColor Red
        }
        "ALERT" 
        {
            Write-Host $LogEntry -ForegroundColor Magenta
        }
    }

    # --------------------------------------------------------
    # File logging
    # --------------------------------------------------------

    try
    {
        $LogDirectoryPath = Split-Path -Path $LogFile -Parent

        if (-not (Test-Path $LogDirectoryPath))
        {
            New-Item -Path $LogDirectoryPath -ItemType Directory -Force | Out-Null
        }

        # Use StremWriter explicitly.
        # This avoids the Add-Content stream issue.
        $Writer = New-Object System.IO.StreamWriter(
            $LogFile,
            $true,
            [System.Text.Encoding]::UTF8
        )
        try
        {
            $Writer.WriteLine($LogEntry)
        }
        finally
        {
            $Writer.Flush()
            $Writer.Dispose()
        }
    }
    catch
    {
        # Never allow logging failure to stop monitoring.
        Write-Host "[LOGGING FAILURE] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================
# STATE FUNCTIONS
# ============================================================

function New-EmptyState {

    return @{
        DCs = @{}
    }
}

# ============================================================

function Load-MonitorState {

    if (-not (Test-Path $StateFile)) {

        Write-MonitorLog `
            "State file does not exist. Creating new state." `
            "INFO"

        return New-EmptyState
    }

    try {

        $Content =
            Get-Content `
                -Path $StateFile `
                -Raw `
                -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Content)) {

            Write-MonitorLog `
                "State file is empty. Creating new state." `
                "WARNING"

            return New-EmptyState
        }

        $Json =
            $Content |
            ConvertFrom-Json

        $State = @{
            DCs = @{}
        }

        if ($null -ne $Json.DCs) {

            foreach ($Property in $Json.DCs.PSObject.Properties) {

                $State.DCs[$Property.Name] =
                    [long]$Property.Value
            }
        }

        return $State
    }

    catch {

        Write-MonitorLog `
            "Unable to load state file. Starting with empty state. Error: $($_.Exception.Message)" `
            "WARNING"

        return New-EmptyState
    }
}

# ============================================================

function Save-MonitorState {

    param (
        [Parameter(Mandatory = $true)]
        $State
    )

    $TempFile = "$StateFile.tmp"

    try {

        # --------------------------------------------------------
        # Convert state to JSON
        # --------------------------------------------------------

        $Json = $State | ConvertTo-Json -Depth 10

        # --------------------------------------------------------
        # Write complete JSON to temporary file
        # --------------------------------------------------------

        [System.IO.File]::WriteAllText(
            $TempFile,
            $Json,
            [System.Text.Encoding]::UTF8
        )

        # --------------------------------------------------------
        # Replace existing state file
        # --------------------------------------------------------

        if (Test-Path $StateFile) {

            Remove-Item `
                -Path $StateFile `
                -Force `
                -ErrorAction Stop
        }

        Move-Item `
            -Path $TempFile `
            -Destination $StateFile `
            -Force `
            -ErrorAction Stop

        Write-MonitorLog `
            "State saved successfully." `
            "INFO"

        return $true
    }
    catch {

        Write-MonitorLog `
            "Unable to save state file: $($_.Exception.Message)" `
            "ERROR"

        return $false
    }
    finally {

        if (Test-Path $TempFile) {

            Remove-Item `
                -Path $TempFile `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# DOMAIN CONTROLLER DISCOVERY
# ============================================================

function Get-ADDomainControllers {

    Write-MonitorLog "Starting Domain Controller discovery..." "INFO"

    # ------------------------------------------------------------
    # Manual DC configuration
    # ------------------------------------------------------------
    if (-not $config.AutoDiscoverDomainControllers) {

        $ConfiguredDCs = @(
            $config.DomainControllers |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } |
            ForEach-Object {
                $_.Trim()
            }
        )

        if ($ConfiguredDCs.Count -eq 0) {
            throw "AutoDiscoverDomainControllers is disabled, but no DomainControllers are configured."
        }

        Write-MonitorLog "Automatic DC discovery is disabled." "INFO"
        Write-MonitorLog "Using configured Domain Controllers:" "INFO"

        foreach ($DC in $ConfiguredDCs) {
            Write-MonitorLog " -> $DC" "INFO"
        }

        return $ConfiguredDCs
    }

    # ------------------------------------------------------------
    # Automatic DC discovery
    # ------------------------------------------------------------
    try {

        Import-Module ActiveDirectory -ErrorAction Stop

        $DomainControllers = @(
            Get-ADDomainController -Filter * -ErrorAction Stop |
            Select-Object -ExpandProperty HostName |
            Sort-Object -Unique
        )

        if ($DomainControllers.Count -eq 0) {
            throw "No Domain Controllers were discovered."
        }

        Write-MonitorLog "ActiveDirectory module discovered $($DomainControllers.Count) Domain Controller(s)." "INFO"

        foreach ($DC in $DomainControllers) {
            Write-MonitorLog " -> $DC" "INFO"
        }

        return $DomainControllers
    }
    catch {

        Write-MonitorLog "Active Directory DC discovery failed: $($_.Exception.Message)" "WARN"

        # Fallback to nltest
        try {

            $Domain = $env:USERDNSDOMAIN

            $NltestOutput = nltest /dclist:$Domain 2>&1

            $DomainControllers = @(
                $NltestOutput |
                Where-Object {
                    $_ -match '\\\\(.+?)\s'
                } |
                ForEach-Object {
                    if ($_ -match '\\\\(.+?)\s') {
                        $Matches[1]
                    }
                } |
                Sort-Object -Unique
            )

            if ($DomainControllers.Count -eq 0) {
                throw "nltest did not return any Domain Controllers."
            }

            Write-MonitorLog "nltest discovered $($DomainControllers.Count) Domain Controller(s)." "INFO"

            foreach ($DC in $DomainControllers) {
                Write-MonitorLog " -> $DC" "INFO"
            }

            return $DomainControllers
        }
        catch {
            throw "Unable to discover Domain Controllers. $($_.Exception.Message)"
        }
    }
}

# ============================================================
# WINDOWS TOAST NOTIFICATION
# ============================================================

function Show-LockoutNotification {

    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$CallerComputer,

        [Parameter(Mandatory = $true)]
        [string]$DomainController,

        [Parameter(Mandatory = $true)]
        [datetime]$LockoutTime,

        [Parameter(Mandatory = $false)]
        [long]$RecordId = 0
    )

    # ============================================================
    # BUILD NOTIFICATION MESSAGE
    # ============================================================

    $Message = @"
AD ACCOUNT LOCKOUT DETECTED

Account:
$Domain\$UserName

Caller Computer:
$CallerComputer

Domain Controller:
$DomainController

Time:
$($LockoutTime.ToString("yyyy-MM-dd HH:mm:ss"))

Event ID:
4740

Record ID:
$RecordId
"@

    # ============================================================
    # CONSOLE ALERT
    # ============================================================

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host "       AD ACCOUNT LOCKOUT DETECTED" -ForegroundColor Red
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host "Account     : $Domain\$UserName" -ForegroundColor Yellow
    Write-Host "Caller      : $CallerComputer" -ForegroundColor Yellow
    Write-Host "DC          : $DomainController" -ForegroundColor Yellow
    Write-Host "Time        : $($LockoutTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
    Write-Host "Event ID    : 4740" -ForegroundColor Yellow

    if ($RecordId -gt 0) {
        Write-Host "Record ID   : $RecordId" -ForegroundColor Yellow
    }

    Write-Host "==============================================" -ForegroundColor Red
    Write-Host ""

    # ============================================================
    # WINDOWS EVENT LOG
    # ============================================================

    if ($config.Notification.Enabled -and
        $config.Notification.WindowsEventLog) {

        try {

            $EventSource = "AD-LockoutMonitor"

            if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {

                New-EventLog `
                    -LogName Application `
                    -Source $EventSource
            }

            Write-EventLog `
                -LogName Application `
                -Source $EventSource `
                -EventId 4740 `
                -EntryType Warning `
                -Message $Message
        }
        catch {

            Write-MonitorLog `
                "Unable to write Windows Event Log notification: $($_.Exception.Message)" `
                "WARN"
        }
    }

    # ============================================================
    # WINDOWS POPUP NOTIFICATION
    # ============================================================

    if ($config.Notification.Enabled) {

        try {

            $NotifyIcon = New-Object System.Windows.Forms.NotifyIcon

            $NotifyIcon.Icon =
                [System.Drawing.SystemIcons]::Warning

            $NotifyIcon.BalloonTipIcon =
                [System.Windows.Forms.ToolTipIcon]::Warning

            $NotifyIcon.BalloonTipTitle =
                "AD ACCOUNT LOCKOUT"

            $NotifyIcon.BalloonTipText = @"
$Domain\$UserName

Caller:
$CallerComputer

DC:
$DomainController

Time:
$($LockoutTime.ToString("HH:mm:ss"))
"@

            $NotifyIcon.Visible = $true

            $NotifyIcon.ShowBalloonTip(10000)

            Start-Sleep -Seconds 10

            $NotifyIcon.Visible = $false
            $NotifyIcon.Dispose()
        }
        catch {

            Write-MonitorLog `
                "Unable to display Windows popup notification: $($_.Exception.Message)" `
                "WARN"
        }
    }
}

# ============================================================
# PARSE EVENT 4740
# ============================================================

function Get-LockoutEventData {

    param (
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$Event
    )

    try {

        [xml]$Xml = $Event.ToXml()

        $Data = @{}

        foreach ($Item in $Xml.Event.EventData.Data) {

            if ($null -ne $Item.Name) {

                $Data[$Item.Name] = [string]$Item.'#text'
            }
        }

        # --------------------------------------------------------
        # Required field
        # --------------------------------------------------------

        $TargetUserName = $null

        if ($Data.ContainsKey("TargetUserName")) {
            $TargetUserName = $Data["TargetUserName"]
        }

        if ([string]::IsNullOrWhiteSpace($TargetUserName)) {

            Write-MonitorLog `
                "Event ID 4740 on $($Event.MachineName) does not contain TargetUserName. RecordId=$($Event.RecordId)." `
                "WARN"

            return $null
        }

        # --------------------------------------------------------
        # Domain
        #
        # SubjectDomainName normally contains MCBLK in your
        # environment.
        # --------------------------------------------------------

        $Domain = "MCBLK"

        if ($Data.ContainsKey("SubjectDomainName")) {

            if (-not [string]::IsNullOrWhiteSpace($Data["SubjectDomainName"])) {

                $Domain = $Data["SubjectDomainName"]
            }
        }

        # --------------------------------------------------------
        # Caller computer
        #
        # In your environment TargetDomainName contains the
        # caller computer name.
        # --------------------------------------------------------

        $CallerComputer = "UNKNOWN"

        if ($Data.ContainsKey("TargetDomainName")) {

            if (-not [string]::IsNullOrWhiteSpace($Data["TargetDomainName"])) {

                $CallerComputer = $Data["TargetDomainName"]
            }
        }

        # --------------------------------------------------------
        # Return normalized object
        # --------------------------------------------------------

        [PSCustomObject]@{

            TargetUserName    = $TargetUserName
            SubjectDomainName = $Domain
            TargetDomainName  = $CallerComputer
            RecordId          = [long]$Event.RecordId
            TimeCreated       = $Event.TimeCreated
            MachineName       = $Event.MachineName
        }
    }
    catch {

        Write-MonitorLog `
            "Unable to parse Event ID 4740 on $($Event.MachineName), RecordId=$($Event.RecordId). Error: $($_.Exception.Message)" `
            "WARN"

        return $null
    }
}

# ============================================================
# PROCESS ONE DOMAIN CONTROLLER
# ============================================================

function Process-DomainController {

    param (
        [Parameter(Mandatory = $true)]
        [string]$DomainController,

        [Parameter(Mandatory = $true)]
        $State
    )

    try {

        Write-MonitorLog `
            "Checking DC: $DomainController" `
            "INFO"

        # ========================================================
        # CHECK WHETHER STATE EXISTS
        # ========================================================

        $HasPreviousState =
            $State.DCs.ContainsKey($DomainController)

        # ========================================================
        # FIRST RUN FOR THIS DC
        # ========================================================

        if (-not $HasPreviousState) {

            Write-MonitorLog `
                "$DomainController has no previous state. Initializing from latest Event ID $EventId." `
                "INFO"

            try {

                $LatestEvent =
                    Get-WinEvent `
                        -ComputerName $DomainController `
                        -FilterHashtable @{
                            LogName = "Security"
                            Id      = $EventId
                        } `
                        -MaxEvents 1 `
                        -ErrorAction SilentlyContinue

            }
            catch {

                $LatestEvent = $null
            }

            if ($null -ne $LatestEvent) {

                $State.DCs[$DomainController] =
                    [long]$LatestEvent.RecordId

                Save-MonitorState -State $State

                Write-MonitorLog `
                    "$DomainController initialized at Record ID $($LatestEvent.RecordId). Historical events will not be alerted." `
                    "INFO"
            }
            else {

                $State.DCs[$DomainController] = 0

                Save-MonitorState -State $State

                Write-MonitorLog `
                    "$DomainController has no Event ID $EventId records." `
                    "INFO"
            }

            return
        }

        # ========================================================
        # GET LAST PROCESSED RECORD ID
        # ========================================================

        $LastRecordId =
            [long]$State.DCs[$DomainController]

        # ========================================================
        # GET RECENT EVENT 4740 RECORDS
        # ========================================================

        try {

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

        }
        catch {

            $Events = @()
        }

        # ========================================================
        # NO EVENTS = NORMAL CONDITION
        # ========================================================

        if ($Events.Count -eq 0) {

            Write-MonitorLog `
                "No Event ID $EventId records found on $DomainController." `
                "INFO"

            return
        }

        # ========================================================
        # FIND ONLY EVENTS AFTER LAST PROCESSED RECORD
        # ========================================================

        $NewEvents =
            @(
                $Events |
                Where-Object {
                    [long]$_.RecordId -gt $LastRecordId
                } |
                Sort-Object RecordId
            )

        # ========================================================
        # NO NEW EVENTS
        # ========================================================

        if ($NewEvents.Count -eq 0) {

            Write-MonitorLog `
                "No new Event ID $EventId events found on $DomainController. Last Record ID: $LastRecordId." `
                "INFO"

            return
        }

        # ========================================================
        # PROCESS NEW EVENTS
        # ========================================================

        foreach ($Event in $NewEvents) {

            try {

                $Lockout =
                    Get-LockoutEventData -Event $Event

                if ($null -eq $Lockout) {

                    Write-MonitorLog `
                        "Unable to parse Event ID $EventId Record ID $($Event.RecordId) on $DomainController." `
                        "WARNING"

                    continue
                }

                # ------------------------------------------------
                # EVENT DETAILS
                # ------------------------------------------------

                $Username =
                    [string]$Lockout.TargetUserName

                $Domain =
                    [string]$Lockout.SubjectDomainName

                $CallerComputer =
                    [string]$Lockout.TargetDomainName

                $LockoutTime =
                    $Event.TimeCreated

                $RecordId =
                    [long]$Event.RecordId

                # ------------------------------------------------
                # SAFETY
                # ------------------------------------------------

                if ([string]::IsNullOrWhiteSpace($Username)) {

                    Write-MonitorLog `
                        "Event ID $EventId Record ID $RecordId has no TargetUserName. Skipping." `
                        "WARNING"

                    continue
                }

                if ([string]::IsNullOrWhiteSpace($Domain)) {
                    $Domain = "MCBLK"
                }

                if ([string]::IsNullOrWhiteSpace($CallerComputer)) {
                    $CallerComputer = "UNKNOWN"
                }

                # ------------------------------------------------
                # LOG DETECTED LOCKOUT
                # ------------------------------------------------

                Write-MonitorLog `
                    "LOCKOUT DETECTED | User=$Username | Domain=$Domain | Caller=$CallerComputer | DC=$DomainController | Time=$LockoutTime | RecordId=$RecordId" `
                    "WARNING"

                # ------------------------------------------------
                # SEND NOTIFICATION
                # ------------------------------------------------

                Show-LockoutNotification `
                    -UserName $Username `
                    -Domain $Domain `
                    -CallerComputer $CallerComputer `
                    -DomainController $DomainController `
                    -LockoutTime $LockoutTime `
                    -RecordId $RecordId

                # ------------------------------------------------
                # UPDATE STATE
                # ------------------------------------------------

                $State.DCs[$DomainController] = $RecordId

                $StateSaved =
                    Save-MonitorState -State $State

                if ($StateSaved) {

                    Write-MonitorLog `
                        "$DomainController state updated to Record ID $RecordId." `
                        "INFO"
                }
                else {

                    Write-MonitorLog `
                        "$DomainController state update FAILED for Record ID $RecordId." `
                        "ERROR"
                }

            }
            catch {

                Write-MonitorLog `
                    "Error processing Event ID $EventId Record ID $($Event.RecordId) on $DomainController. Error: $($_.Exception.Message)" `
                    "ERROR"
            }
        }

    }
    catch {

        Write-MonitorLog `
            "Unable to process $DomainController. Error: $($_.Exception.Message)" `
            "ERROR"
    }
}

# ============================================================
# STARTUP INFORMATION
# ============================================================

Write-Host ""
Write-Host "====================================================" `
    -ForegroundColor Cyan

Write-Host "       AD ACCOUNT LOCKOUT MONITOR" `
    -ForegroundColor Cyan

Write-Host "====================================================" `
    -ForegroundColor Cyan

Write-Host "Version               : 1.0.0"
Write-Host "Author                : Madhushanka Lakmal"
Write-Host "Automatic DC discovery: $AutoDiscover"
Write-Host "Event ID              : $EventId"
Write-Host "Check interval        : $CheckIntervalSeconds seconds"
Write-Host "DC rediscovery        : Every $RediscoverDCsEveryMinutes minutes"
Write-Host "Windows notification  : $NotificationEnabled"

Write-Host "====================================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-MonitorLog `
    "====================================================" `
    "INFO"

Write-MonitorLog `
    "AD ACCOUNT LOCKOUT MONITOR STARTED - Version 1.0.0" `
    "INFO"

Write-MonitorLog `
    "Author: Madhushanka Lakmal" `
    "INFO"

Write-MonitorLog `
    "====================================================" `
    "INFO"

# ============================================================
# LOAD STATE
# ============================================================

$State =
    Load-MonitorState

# ============================================================
# INITIAL DOMAIN CONTROLLER DISCOVERY
# ============================================================

$DomainControllers =
    @(
        Get-ADDomainControllers
    )

if ($DomainControllers.Count -eq 0) {

    Write-MonitorLog `
        "No Domain Controllers discovered. Monitor cannot continue." `
        "ERROR"

    exit 1
}

Write-MonitorLog `
    "Discovered Domain Controllers:" `
    "INFO"

foreach ($DC in $DomainControllers) {

    Write-MonitorLog `
        " -> $DC" `
        "INFO"
}

# ============================================================
# INITIALIZE STATE FOR ALL DCs
# ============================================================

foreach ($DC in $DomainControllers) {

    Process-DomainController `
        -DomainController $DC `
        -State $State
}

# ============================================================
# REDISCOVERY TIMER
# ============================================================

$LastRediscovery =
    Get-Date

# ============================================================
# MAIN MONITORING LOOP
# ============================================================

while ($true) {

    try {

        # ----------------------------------------------------
        # CHECK WHETHER DC REDISCOVERY IS REQUIRED
        # ----------------------------------------------------

        $CurrentTime =
            Get-Date

        $MinutesSinceRediscovery =
            (
                $CurrentTime -
                $LastRediscovery
            ).TotalMinutes

        if (
            $MinutesSinceRediscovery `
                -ge `
            $RediscoverDCsEveryMinutes
        ) {

            Write-MonitorLog `
                "Rediscovering Domain Controllers..." `
                "INFO"

            $NewDomainControllers =
                @(
                    Get-ADDomainControllers
                )

            if ($NewDomainControllers.Count -gt 0) {

                $DomainControllers =
                    $NewDomainControllers

                Write-MonitorLog `
                    "Current Domain Controllers:" `
                    "INFO"

                foreach ($DC in $DomainControllers) {

                    Write-MonitorLog `
                        " -> $DC" `
                        "INFO"
                }
            }
            else {

                Write-MonitorLog `
                    "DC rediscovery returned no Domain Controllers. Keeping previous list." `
                    "WARNING"
            }

            $LastRediscovery =
                Get-Date
        }

        # ----------------------------------------------------
        # MONITOR ALL DOMAIN CONTROLLERS
        # ----------------------------------------------------

        foreach ($DC in $DomainControllers) {

            Process-DomainController `
                -DomainController $DC `
                -State $State
        }

    }
    catch {

        Write-MonitorLog `
            "Main monitoring loop error: $($_.Exception.Message)" `
            "ERROR"
    }

    # --------------------------------------------------------
    # WAIT BEFORE NEXT CHECK
    # --------------------------------------------------------

    Start-Sleep `
        -Seconds $CheckIntervalSeconds
}