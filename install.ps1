# Claude Code Statusline — Windows installer (PowerShell 5.1+).
#
# Usage:
#   .\install.ps1                    # install statusline.js (Node, default)
#   .\install.ps1 -Runner ps1        # install statusline.ps1 (native PowerShell, no Node)
#   .\install.ps1 -Runner sh         # install statusline.sh (legacy, deprecated)
#   .\install.ps1 -Source <path>     # install from a local file instead of HTTP
#   .\install.ps1 -DryRun            # backup + plan only; no download or settings edit
#
# Pre-existing files in $env:USERPROFILE\.claude (statusline.{sh,js,ps1},
# settings.json) are backed up to *.bak.<yyyyMMdd-HHmmss> before any change.
# Backup paths are printed on exit.

[CmdletBinding()]
param(
    [ValidateSet("js", "ps1", "sh")]
    [string]$Runner = "js",

    [string]$Source = "",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($Runner -eq "sh") {
    Write-Warning ("--Runner sh is deprecated. The shell runner depends on jq and " +
        "coreutils which break on Windows. The Node runner is now canonical. See " +
        "the README 'Migration' section for the staged removal timeline.")
}

$RepoRaw   = "https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings  = Join-Path $ClaudeDir "settings.json"

if ($Runner -eq "js") {
    $Dest = Join-Path $ClaudeDir "statusline.js"
    $Src  = "statusline.js"
    $Cmd  = "node `"$Dest`""
} elseif ($Runner -eq "ps1") {
    $Dest = Join-Path $ClaudeDir "statusline.ps1"
    $Src  = "statusline.ps1"
    $Cmd  = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Dest`""
} else {
    $Dest = Join-Path $ClaudeDir "statusline.sh"
    $Src  = "statusline.sh"
    $Cmd  = "`"$Dest`""
}

# Node version gate (js mode only).
if ($Runner -eq "js") {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        throw "node v18+ required but not found on PATH."
    }
    $version = (& node -e "process.stdout.write(String(process.versions.node.split('.')[0]))" 2>$null)
    if ([int]$version -lt 18) {
        throw "node v18+ required (found v$version)."
    }
}

# PowerShell version gate (ps1 mode only).
if ($Runner -eq "ps1") {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))."
    }
}

# Ensure ~/.claude exists.
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
}

# Timestamped backup of any pre-existing assets. Bail on first failure.
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backups = @()
foreach ($f in @(
    (Join-Path $ClaudeDir "statusline.sh"),
    (Join-Path $ClaudeDir "statusline.js"),
    (Join-Path $ClaudeDir "statusline.ps1"),
    $Settings
)) {
    if (Test-Path $f) {
        $bak = "$f.bak.$ts"
        Copy-Item -Path $f -Destination $bak -ErrorAction Stop
        $backups += $bak
    }
}

if ($DryRun) {
    Write-Host "dry-run: backups created (no download or settings edit)."
    if ($backups.Count -gt 0) {
        Write-Host "backups:"
        foreach ($b in $backups) { Write-Host "  $b" }
    }
    exit 0
}

# Atomic download: write to tmp, then Move-Item -Force onto destination.
$tmp = New-TemporaryFile
try {
    if ($Source -ne "") {
        Copy-Item -Path $Source -Destination $tmp.FullName -Force
    } else {
        Invoke-WebRequest -Uri "$RepoRaw/$Src" -OutFile $tmp.FullName -UseBasicParsing
    }
    Move-Item -Path $tmp.FullName -Destination $Dest -Force
} catch {
    Remove-Item -Path $tmp.FullName -ErrorAction SilentlyContinue
    throw
}

# Update settings.json. ConvertFrom-Json + ConvertTo-Json round-trip preserves
# unrelated keys; -Depth 10 covers nested hook/permission objects.
$line = [PSCustomObject]@{
    type    = "command"
    command = $Cmd
    padding = 0
}

if (Test-Path $Settings) {
    # Read as raw UTF-8 bytes — Get-Content -Raw in PS 5.1 defaults to the
    # ANSI code page (cp949 on Korean Windows etc.) and corrupts non-ASCII
    # JSON values (e.g. Korean hook command strings).
    $raw = [System.IO.File]::ReadAllText($Settings, (New-Object System.Text.UTF8Encoding($false)))
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $obj = [PSCustomObject]@{}
    } else {
        $obj = $raw | ConvertFrom-Json
    }
    if ($obj.PSObject.Properties.Name -contains "statusLine") {
        $obj.statusLine = $line
    } else {
        Add-Member -InputObject $obj -MemberType NoteProperty -Name "statusLine" -Value $line
    }
    # Write back as UTF-8 without BOM to preserve compatibility with the
    # Node-based Claude Code reader.
    $json = $obj | ConvertTo-Json -Depth 10
    $tmpJson = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpJson, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmpJson -Destination $Settings -Force
} else {
    $obj = [PSCustomObject]@{ statusLine = $line }
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Settings, $json, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "installed ($Runner). restart Claude Code to apply."
if ($backups.Count -gt 0) {
    Write-Host "backups:"
    foreach ($b in $backups) { Write-Host "  $b" }
}
