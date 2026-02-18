$ErrorActionPreference = "SilentlyContinue"

# ===== CONFIG =====
$RemoteHost = "coldstore-dataharvest-49.ru"
$Proto      = "smb"
$Port       = 445
$MinSeconds = 12 * 60
$MaxSeconds = 18 * 60
$RunSeconds = Get-Random -Min $MinSeconds -Max $MaxSeconds

$StartTime = Get-Date
$EndTime   = $StartTime.AddSeconds($RunSeconds)
# ===== HELPERS =====
function PrintETA {
    param(
        [DateTime]$StartTime,
        [DateTime]$EndTime
    )

    $elapsed = (Get-Date) - $StartTime
    $remaining = ($EndTime - (Get-Date)).TotalSeconds
    if ($remaining -le 0) { return }

    # Phase logic:
    # First 35% of runtime → ETA pessimistic (gets worse)
    # Middle 30%         → unstable
    # Final 35%          → converges nicely
    $total = ($EndTime - $StartTime).TotalSeconds
    $progress = $elapsed.TotalSeconds / $total

    if ($progress -lt 0.35) {
        # Early pessimism
        $jitter = Get-Random -Min 90 -Max 220
    }
    elseif ($progress -lt 0.65) {
        # Unstable middle
        $jitter = Get-Random -Min -60 -Max 120
    }
    else {
        # Converging end
        $jitter = Get-Random -Min -30 -Max 20
    }

    $eta = [Math]::Max(0, [int]($remaining + $jitter))
    $m = [int]($eta / 60)
    $s = $eta % 60

    Write-Host ("[work] Estimated time remaining: {0}m {1}s" -f $m,$s) `
        -ForegroundColor DarkGray
}

function SleepJ([int]$min=180,[int]$max=850){
    Start-Sleep -Milliseconds (Get-Random -Min $min -Max $max)
}

function Line($tag,$msg,$color="Gray"){
    Write-Host ("[{0}] {1}" -f $tag,$msg) -ForegroundColor $color
    SleepJ
}

function Progress {
    $pct = Get-Random -Min 2 -Max 99
    $mbs = [Math]::Round((Get-Random -Min 18 -Max 160) + (Get-Random), 1)
    $rtt = Get-Random -Min 18 -Max 120
    Write-Host ("[sftp] {0}% | {1} MB/s | RTT {2} ms" -f $pct,$mbs,$rtt) -ForegroundColor DarkCyan
    SleepJ 220 1100
}

function FormatBytes([Int64]$b){
    if ($b -ge 1TB) { "{0:N2} TB" -f ($b/1TB) }
    elseif ($b -ge 1GB) { "{0:N2} GB" -f ($b/1GB) }
    elseif ($b -ge 1MB) { "{0:N2} MB" -f ($b/1MB) }
    elseif ($b -ge 1KB) { "{0:N2} KB" -f ($b/1KB) }
    else { "$b B" }
}

# ===== BOOT =====
Line "init" "Starting data harvest to analysis endpoint" "Magenta"
Line "init" "Loading transfer profile: databreach-transfer" "DarkCyan"
Line "net"  "Resolving host $RemoteHost" "DarkCyan"
Line "net"  "Connecting via $Proto:$Port" "DarkCyan"
Line "net"  "SSH handshake complete. Host key verified." "DarkCyan"
Line "net"  "Negotiated KEX: curve25519-sha256 | Cipher: chacha20-poly1305" "DarkCyan"
Line "net"  "SFTP subsystem initialized" "DarkCyan"
Line "auth" "Session authorized (scope: archive.write)" "DarkCyan"

# ===== ENUMERATE REAL FILES (METADATA ONLY) =====
Line "scan" "Enumerating local user datasets" "Yellow"

$drives = Get-CimInstance Win32_LogicalDisk |
  Where-Object { $_.DriveType -eq 3 } |
  Select-Object -ExpandProperty DeviceID

$profiles = @()
foreach ($d in $drives) {
    $u = "$d\Users"
    if (Test-Path $u) {
        Get-ChildItem $u -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -notin @("Public","Default","Default User","All Users") } |
          ForEach-Object { $profiles += $_.FullName }
    }
}

if ($profiles.Count -eq 0) {
    Line "scan" "No user profiles detected. Job exiting." "Yellow"
    exit 0
}

$folders = @("Desktop","Documents","Downloads","Pictures","Videos","Music")
$files = New-Object System.Collections.Generic.List[object]

foreach ($p in $profiles) {
    foreach ($f in $folders) {
        $path = Join-Path $p $f
        if (-not (Test-Path $path)) { continue }

        Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 8 |
          ForEach-Object { $files.Add($_) }

        if ($files.Count -ge 120) { break }
    }
    if ($files.Count -ge 120) { break }
}

Line "stage" ("Prepared {0} items for staging (metadata scan)" -f $files.Count) "Green"
Progress

# ===== REALISTIC FILE LIST =====
Line "manifest" "Writing transfer manifest" "DarkCyan"

foreach ($f in ($files | Sort-Object Length -Descending | Select-Object -First 70)) {
    $ts = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $sz = FormatBytes $f.Length
    Write-Host ("  {0}  {1,10}  {2}" -f $ts,$sz,$f.FullName) -ForegroundColor Green
    Start-Sleep -Milliseconds (Get-Random -Min 40 -Max 160)
}

# ===== FAKE TRANSFER PHASE =====
Line "sftp" "Creating remote staging directory" "DarkCyan"
Progress
Line "sftp" "Uploading manifest.json" "DarkCyan"
Progress
Line "sftp" "Uploading archive chunks" "DarkCyan"

for ($i=0; $i -lt 8; $i++) { Progress }

# boring remote-side chatter (once)
Write-Host "[remote] Принял. Идёт обычная загрузка, без приоритета." -ForegroundColor DarkGray
SleepJ 800 1600

Line "verify" "Verifying remote checksums" "DarkYellow"
for ($i=0; $i -lt 5; $i++) { Progress }

# ===== KEEP IT RUNNING ~15 MIN =====
Line "work" "Entering steady-state transfer window" "DarkCyan"

while ((Get-Date) -lt $EndTime) {
    $ops = @(
      "Flushing buffers",
      "Reconciling chunk table",
      "Validating manifest offsets",
      "Replaying integrity journal",
      "Normalizing path index",
      "Checking remote free space",
      "Maintaining keepalive"
    )

    Line "work" (Get-Random $ops) "DarkCyan"
    Progress

    if ((Get-Random -Min 1 -Max 4) -eq 2) {
        PrintETA -StartTime $StartTime -EndTime $EndTime
    }
}

# ===== FINISH =====
Line "sftp" "Finalizing transaction (fsync)" "DarkCyan"
Progress
Line "ok" "Transfer completed successfully" "Green"
$Elapsed = New-TimeSpan -Start $StartTime -End (Get-Date)
Line "done" ("Runtime: {0}m {1}s" -f $Elapsed.Minutes,$Elapsed.Seconds) "Magenta"
Line "info" "Session closed by remote peer" "DarkGray"
Start-Sleep -Seconds 10
exit
