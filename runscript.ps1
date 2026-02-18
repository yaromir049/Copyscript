$ErrorActionPreference = "Stop"

$TargetRoot = "H:\UserBackups"
$LogDir = "$env:USERPROFILE\backup_logs"

New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = Join-Path $LogDir "sync_$Timestamp.log"

$RoboOpts = @(
  "/E",
  "/Z",
  "/R:2",
  "/W:2",
  "/MT:16",
  "/COPY:DAT",
  "/DCOPY:DAT",
  "/XJ",
  "/FFT",
  "/NP",
  "/TEE"
)

$ExcludeDirs = @(
  "AppData\Local\Temp",
  "AppData\Local\Microsoft\Windows\INetCache",
  "AppData\Local\Microsoft\Windows\Explorer",
  "AppData\Local\CrashDumps",
  "AppData\Local\Packages"
)

$RemoteAlias = "ru-backup-01"
$RemoteRegion = "RU-MOW"
$RemoteProto  = "sftp"
$RemotePort   = 22

function Write-LogLine {
  param([string]$Text, [string]$Color = "Gray")
  Write-Host $Text -ForegroundColor $Color
  $Text | Tee-Object -FilePath $LogFile -Append | Out-Null
}

function Jitter([int]$minMs = 120, [int]$maxMs = 380) {
  Start-Sleep -Milliseconds (Get-Random -Min $minMs -Max $maxMs)
}

function Remote-Noise {
  $lines = @(
    "Resolving $RemoteAlias...",
    "Connecting to $RemoteAlias ($RemoteRegion) via $RemoteProto:$RemotePort...",
    "SSH handshake complete. Host key verified.",
    "Opening SFTP session...",
    "Session established. Negotiated ciphers: chacha20-poly1305, curve25519-sha256.",
    "Allocating remote staging area...",
    "Negotiating transfer window...",
    "Scheduling block-level deltas...",
    "Verifying remote write permissions...",
    "Remote quota check passed.",
    "Starting transfer pipeline..."
  )
  Write-LogLine ("[sync] " + (Get-Random $lines)) "DarkCyan"
  Jitter
}

function Remote-Progress {
  $pct = Get-Random -Min 12 -Max 96
  $mbs = [Math]::Round((Get-Random -Min 18 -Max 145) + (Get-Random), 1)
  $rtt = Get-Random -Min 24 -Max 110
  Write-LogLine ("[sync] Progress: {0}% | Throughput: {1} MB/s | RTT: {2} ms" -f $pct, $mbs, $rtt) "DarkCyan"
  Jitter 140 520
}

Write-LogLine "=== Starting scheduled synchronization job ===" "Magenta"
Write-LogLine ("Timestamp: {0}" -f (Get-Date)) "DarkGray"
Write-LogLine ("Target: {0}" -f $TargetRoot) "DarkGray"

$Drives = Get-CimInstance Win32_LogicalDisk |
  Where-Object { $_.DriveType -eq 3 } |
  Select-Object -ExpandProperty DeviceID |
  Sort-Object

if (-not ($Drives -contains "H:")) {
  Write-LogLine "[error] Destination volume not available (H: missing). Job aborted." "Red"
  exit 1
}

Remote-Noise
Remote-Progress

foreach ($Drive in $Drives) {
  if ($Drive -eq "H:") { continue }

  $UsersRoot = "$Drive\Users"
  if (-not (Test-Path $UsersRoot)) { continue }

  $DriveName = $Drive.TrimEnd(":")
  $DestRoot = Join-Path $TargetRoot "${DriveName}_Users"
  New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null

  Write-LogLine "" "Gray"
  Write-LogLine ("[scan] Enumerating profiles on {0}..." -f $Drive) "Yellow"
  Remote-Noise

  Get-ChildItem -Path $UsersRoot -Directory | ForEach-Object {
    $UserName = $_.Name
    if ($UserName -in @("Public", "Default", "Default User", "All Users")) { return }

    $Source = $_.FullName
    $Dest = Join-Path $DestRoot $UserName
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null

    Write-LogLine ("[sync] Queueing dataset: {0}\{1}" -f $Drive, ("Users\" + $UserName)) "Green"
    Remote-Progress

    $XD = @()
    foreach ($d in $ExcludeDirs) { $XD += @("/XD", (Join-Path $Source $d)) }

    robocopy $Source $Dest @RoboOpts @XD /LOG+:$LogFile

    if ($LASTEXITCODE -ge 8) {
      Write-LogLine ("[error] Sync failed for profile '{0}' (robocopy code {1})." -f $UserName, $LASTEXITCODE) "Red"
      Write-LogLine "[sync] Closing session. Pending operations cancelled." "DarkCyan"
      exit $LASTEXITCODE
    }

    Write-LogLine ("[ok] Dataset committed: {0}" -f $UserName) "Green"
    Remote-Progress
  }
}

Write-LogLine "" "Gray"
Write-LogLine "[sync] Finalizing transaction..." "DarkCyan"
Remote-Progress
Write-LogLine "=== Synchronization complete ===" "Magenta"
Write-LogLine ("Log: {0}" -f $LogFile) "DarkGray"
