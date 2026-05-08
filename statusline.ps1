# SPDX-License-Identifier: MIT
# ============================================================================
# Claude Code Statusline - 4-line axis-separated layout (PowerShell port)
# ============================================================================
#
# Native Windows PowerShell 5.1+ port of statusline.sh / statusline.js.
# Zero external dependencies: no node, no jq, no coreutils. Only built-ins
# and (optionally) git.
#
# Layout:
#   Line 1: Filesystem  - cwd (dim prefix + bold basename)
#   Line 2: Git         - worktree(conditional) | branch | clean/dirty
#   Line 3: AI          - model | context bar pct | used/max | tenancy?
#   Line 4: Resources   - cost | 5h bar pct (reset) | Week bar pct (reset) | vim
#
# Notes for Korean / non-UTF-8 default Windows installs: this script writes
# raw UTF-8 bytes directly to stdout (bypassing $OutputEncoding / cp949) so
# bar glyphs (filled/empty block) and other non-ASCII chars survive intact.
# ============================================================================

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# ----------------------------------
# Config - CCSL_<NAME> env overrides, identical defaults to statusline.{sh,js}
# ----------------------------------
function Get-NumEnv {
    param([string]$Key, [double]$Default)
    $v = [Environment]::GetEnvironmentVariable($Key)
    if ([string]::IsNullOrEmpty($v)) { return $Default }
    $n = 0.0
    if ([double]::TryParse($v, [ref]$n)) { return $n }
    return $Default
}

$CFG = @{
    BAR_WIDTH      = [int](Get-NumEnv 'CCSL_BAR_WIDTH'      10)
    CTX_WARN       = [int](Get-NumEnv 'CCSL_CTX_WARN'       50)
    CTX_CRIT       = [int](Get-NumEnv 'CCSL_CTX_CRIT'       80)
    FIRE_THRESHOLD = [int](Get-NumEnv 'CCSL_FIRE_THRESHOLD' 90)
    LIMIT_WARN_MIN = [int](Get-NumEnv 'CCSL_LIMIT_WARN_MIN' 15)
    GIT_TIMEOUT    = [int](Get-NumEnv 'CCSL_GIT_TIMEOUT'     1)
}
$_costWarn = [Environment]::GetEnvironmentVariable('CCSL_COST_WARN')
$_costCrit = [Environment]::GetEnvironmentVariable('CCSL_COST_CRIT')
if ([string]::IsNullOrEmpty($_costWarn)) { $_costWarn = '2.0' }
if ([string]::IsNullOrEmpty($_costCrit)) { $_costCrit = '5.0' }
$CFG.COST_WARN = $_costWarn
$CFG.COST_CRIT = $_costCrit

# ----------------------------------
# ANSI colors
# ----------------------------------
$ESC = [char]27
$C = @{
    RESET       = "$ESC[0m"
    BOLD        = "$ESC[1m"
    FG_CYAN     = "$ESC[38;5;80m"
    FG_GREEN    = "$ESC[38;5;114m"
    FG_YELLOW   = "$ESC[38;5;179m"
    FG_RED      = "$ESC[38;5;203m"
    FG_PINK     = "$ESC[38;5;218m"
    FG_BLUE     = "$ESC[38;5;111m"
    FG_LAVENDER = "$ESC[38;5;147m"
    FG_MUTED    = "$ESC[38;5;246m"
    FG_SEP      = "$ESC[38;5;242m"
    FG_DIM      = "$ESC[38;5;238m"
}
$SEP = "  $($C.FG_SEP)" + [char]0x00B7 + "$($C.RESET)  "

# ----------------------------------
# Helpers
# ----------------------------------
function Make-Bar {
    param([int]$Pct, [int]$Width = $CFG.BAR_WIDTH)
    $p = $Pct
    if ($p -lt 0)   { $p = 0 }
    if ($p -gt 100) { $p = 100 }
    $filled = [int][Math]::Floor($p * $Width / 100)
    $empty  = $Width - $filled
    $f = ''
    $e = ''
    if ($filled -gt 0) { $f = ([char]0x25B0).ToString() * $filled }
    if ($empty  -gt 0) { $e = ([char]0x25B1).ToString() * $empty }
    return "$f$($C.FG_DIM)$e$($C.RESET)"
}

function Color-ByPct {
    param([int]$Pct)
    if ($Pct -lt $CFG.CTX_WARN) { return $C.FG_GREEN }
    if ($Pct -lt $CFG.CTX_CRIT) { return $C.FG_YELLOW }
    return $C.FG_RED
}

function Format-Tokens {
    param([long]$N)
    if ($N -ge 1000000) {
        $tenths = [long][Math]::Floor($N / 100000)
        return "{0}.{1}M" -f [long][Math]::Floor($tenths / 10), ($tenths % 10)
    }
    if ($N -ge 1000) {
        return "{0}k" -f [long][Math]::Floor(($N + 500) / 1000)
    }
    return "$N"
}

# Mirror bash _to_cents: string-parse to avoid float drift.
function To-Cents {
    param($V)
    $s = if ($null -eq $V) { '' } else { [string]$V }
    if ([string]::IsNullOrEmpty($s)) { return 0 }
    if ($s.Contains('.')) {
        $parts = $s.Split('.', 2)
        $iPart = $parts[0]
        $rest  = if ($parts.Length -gt 1) { $parts[1] } else { '' }
        $f = ($rest + '00').Substring(0, [Math]::Min(2, ($rest + '00').Length))
        $iVal = 0; [void][int]::TryParse($iPart, [ref]$iVal)
        $fVal = 0; [void][int]::TryParse($f,     [ref]$fVal)
        return $iVal * 100 + $fVal
    }
    $iVal = 0; [void][int]::TryParse($s, [ref]$iVal)
    return $iVal * 100
}

function Pad3 {
    param($N)
    return ([string]$N).PadLeft(3, ' ')
}

# ----------------------------------
# Stdin - synchronous read of the JSON payload CC writes before closing pipe
# ----------------------------------
function Read-Stdin {
    if (-not [Console]::IsInputRedirected) { return '' }
    try {
        return [Console]::In.ReadToEnd()
    } catch {
        return ''
    }
}

function Parse-Input {
    $raw = (Read-Stdin) -replace "`0", ''
    $raw = $raw.Trim()
    if ([string]::IsNullOrEmpty($raw)) { return $null }
    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Has-Prop {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $false }
    if ($Obj -isnot [psobject]) { return $false }
    return ($null -ne $Obj.PSObject.Properties[$Name])
}

function Get-Prop {
    param($Obj, [string]$Name, $Default = $null)
    if (Has-Prop $Obj $Name) { return $Obj.$Name }
    return $Default
}

# ----------------------------------
# git - spawn with bounded wait so a hung repo can't stall the prompt
# ----------------------------------
function Git-Safe {
    param([string]$Cwd, [string[]]$ArgList)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        # PS 5.1 ProcessStartInfo only exposes the Arguments string. Quote any
        # arg containing whitespace so multi-word values survive intact.
        $quoted = $ArgList | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }
        $psi.Arguments              = ($quoted -join ' ')
        $psi.WorkingDirectory       = $Cwd
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.EnvironmentVariables['LC_ALL'] = 'C'

        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $proc) { return $null }
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $timeoutMs  = [int]($CFG.GIT_TIMEOUT * 1000)
        if (-not $proc.WaitForExit($timeoutMs)) {
            try { $proc.Kill() } catch {}
            return $null
        }
        if ($proc.ExitCode -ne 0) { return $null }
        $out = $stdoutTask.Result
        if ($null -eq $out) { return $null }
        return ($out -replace "(`r?`n)+$", '')
    } catch {
        return $null
    }
}

# ----------------------------------
# Tenancy - read oauthAccount from ~/.claude.json
# ----------------------------------
function Read-Tenancy {
    try {
        $homeDir = $env:USERPROFILE
        if ([string]::IsNullOrEmpty($homeDir)) { $homeDir = [Environment]::GetFolderPath('UserProfile') }
        if ([string]::IsNullOrEmpty($homeDir)) { return $null }
        $f = Join-Path $homeDir '.claude.json'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $raw = Get-Content -LiteralPath $f -Raw -ErrorAction Stop
        $j   = $raw | ConvertFrom-Json -ErrorAction Stop
        $a   = Get-Prop $j 'oauthAccount'
        if ($null -eq $a) { return $null }
        $orgName     = Get-Prop $a 'organizationName' ''
        $displayName = Get-Prop $a 'displayName'      ''
        $email       = Get-Prop $a 'emailAddress'     ''
        if ([string]::IsNullOrEmpty($displayName) -and [string]::IsNullOrEmpty($email)) { return $null }
        return @{ OrgName = $orgName; DisplayName = $displayName; Email = $email }
    } catch {
        return $null
    }
}

function Format-Tenancy {
    param($T)
    if ($null -eq $T) { return '' }
    $name = $T.DisplayName
    if ([string]::IsNullOrEmpty($name) -and -not [string]::IsNullOrEmpty($T.Email)) {
        $name = $T.Email.Split('@')[0]
    }
    if ([string]::IsNullOrEmpty($name)) { return '' }
    if ([string]::IsNullOrEmpty($T.OrgName) -or $T.OrgName -match "'s (Individual )?Organization$") {
        return "@ $($C.FG_LAVENDER)$name$($C.RESET)"
    }
    return "@ $($C.FG_LAVENDER)$name$($C.RESET) $($C.FG_SEP)($($C.RESET)$($C.FG_BLUE)$($T.OrgName)$($C.RESET)$($C.FG_SEP))$($C.RESET)"
}

# ----------------------------------
# Line 1 - cwd (dim parent + bold basename, "~" expansion)
# ----------------------------------
function Render-Line1 {
    param([string]$Cwd)
    $p = $Cwd
    $homeDir = $env:USERPROFILE
    if (-not [string]::IsNullOrEmpty($homeDir) -and $p.StartsWith($homeDir, [StringComparison]::OrdinalIgnoreCase)) {
        $p = '~' + $p.Substring($homeDir.Length)
    }
    # Treat both / and \ as separators (matches Node port behavior on Windows).
    $idx = [Math]::Max($p.LastIndexOf('\'), $p.LastIndexOf('/'))
    if ($idx -lt 0 -or $idx -eq $p.Length - 1) {
        return "$($C.FG_CYAN)$($C.BOLD)$p$($C.RESET)"
    }
    $base   = $p.Substring($idx + 1)
    $prefix = $p.Substring(0, $idx + 1)
    if ([string]::IsNullOrEmpty($base)) {
        return "$($C.FG_CYAN)$($C.BOLD)$p$($C.RESET)"
    }
    return "$($C.FG_MUTED)$prefix$($C.RESET)$($C.FG_CYAN)$($C.BOLD)$base$($C.RESET)"
}

# ----------------------------------
# Line 2 - git info with 5s per-CWD file cache
# ----------------------------------
$CACHE_TTL = 5

function Cache-Dir {
    $user = 'user'
    try {
        $u = $env:USERNAME
        if (-not [string]::IsNullOrEmpty($u)) {
            $user = ($u -replace '[^a-zA-Z0-9_-]', '_')
        }
    } catch {}
    return (Join-Path $env:TEMP "claude-code-statusline-$user")
}

function Compute-Line2 {
    param([string]$Cwd, [string]$WtName)

    if ($null -eq (Git-Safe $Cwd @('rev-parse', '--git-dir'))) {
        return "$($C.FG_DIM)(no git repo)$($C.RESET)"
    }

    $branch = Git-Safe $Cwd @('symbolic-ref', '--short', 'HEAD')
    if ($null -eq $branch) {
        $branch = Git-Safe $Cwd @('rev-parse', '--abbrev-ref', 'HEAD')
    }
    if ([string]::IsNullOrEmpty($branch) -or $branch -eq 'HEAD') { $branch = 'detached' }

    $wtPart = ''
    if (-not [string]::IsNullOrEmpty($WtName)) {
        $wtPart = ([char]0x2325).ToString() + " $($C.FG_LAVENDER)wt:$WtName$($C.RESET)$SEP"
    } else {
        $gitDir = Git-Safe $Cwd @('rev-parse', '--git-dir')
        if ($null -ne $gitDir -and ($gitDir -replace '\\', '/').Contains('/.git/worktrees/')) {
            $wtRoot = Git-Safe $Cwd @('rev-parse', '--show-toplevel')
            if ($null -eq $wtRoot) { $wtRoot = '' }
            $fallback = ($wtRoot -replace '\\', '/').Split('/')[-1]
            $wtPart = ([char]0x2325).ToString() + " $($C.FG_LAVENDER)wt:$fallback$($C.RESET)$SEP"
        }
    }

    $porcelain = Git-Safe $Cwd @('status', '--porcelain')
    if ($null -eq $porcelain) { $porcelain = '' }
    if ([string]::IsNullOrEmpty($porcelain)) {
        $statusPart = ([char]0x2713).ToString() + " $($C.FG_GREEN)clean$($C.RESET)"
    } else {
        $files = ($porcelain -split "`r?`n" | Where-Object { $_.Length -gt 0 }).Count
        $shortstat = Git-Safe $Cwd @('diff', '--shortstat', 'HEAD')
        if ($null -eq $shortstat) { $shortstat = '' }
        $added = '0'
        $deleted = '0'
        $m = [regex]::Match($shortstat, '(\d+)\s+insertion')
        if ($m.Success) { $added = $m.Groups[1].Value }
        $m = [regex]::Match($shortstat, '(\d+)\s+deletion')
        if ($m.Success) { $deleted = $m.Groups[1].Value }
        $statusPart = [char]0x00B1 + " $($C.FG_RED)$files files$($C.RESET) $($C.FG_SEP)" + [char]0x00B7 + "$($C.RESET) $($C.FG_GREEN)+$added$($C.RESET) $($C.FG_RED)" + [char]0x2212 + "$deleted$($C.RESET)"
    }

    $branchGlyph = [char]0x2387
    return "$wtPart$branchGlyph $($C.FG_YELLOW)$branch$($C.RESET)$SEP$statusPart"
}

function Render-Line2 {
    param([string]$Cwd, [string]$WtName)
    $key = ($Cwd -replace '[^a-zA-Z0-9_-]', '_')
    $dir = Cache-Dir
    $cacheFile = Join-Path $dir "git-$key.cache"

    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $st = Get-Item -LiteralPath $cacheFile -ErrorAction Stop
            $ageSec = ((Get-Date) - $st.LastWriteTime).TotalSeconds
            if ($ageSec -lt $CACHE_TTL) {
                return (Get-Content -LiteralPath $cacheFile -Raw -Encoding UTF8)
            }
        } catch {}
    }

    $out = Compute-Line2 $Cwd $WtName

    try {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $tmp = "$cacheFile.tmp.$PID"
        [System.IO.File]::WriteAllText($tmp, $out, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $cacheFile -Force
    } catch {}

    return $out
}

# ----------------------------------
# Line 3 - model | context bar | used/max | tenancy?
# ----------------------------------
function Render-Line3 {
    param([string]$Model, [int]$CtxPct, [long]$CtxUsed, [long]$CtxMax)
    $color   = Color-ByPct $CtxPct
    $bar     = Make-Bar  $CtxPct
    $extra   = if ($CtxPct -ge $CFG.FIRE_THRESHOLD) { ' !' } else { '' }
    $usedFmt = Format-Tokens $CtxUsed
    $maxFmt  = Format-Tokens $CtxMax
    $t       = Read-Tenancy
    $suffix  = if ($null -ne $t) { "$SEP$(Format-Tenancy $t)" } else { '' }
    $star    = [char]0x2726
    return "$star $($C.FG_PINK)$Model$($C.RESET)$SEP$bar  $color$($C.BOLD)$(Pad3 $CtxPct)%$($C.RESET)$extra $($C.FG_SEP)" + [char]0x00B7 + "$($C.RESET) $($C.FG_MUTED)$usedFmt / $maxFmt$($C.RESET)$suffix"
}

# ----------------------------------
# Line 4 - cost | 5h | Week | vim mode
# ----------------------------------
function Format-Cost {
    param($Cost)
    $ci = To-Cents $Cost
    $cw = To-Cents $CFG.COST_WARN
    $cc = To-Cents $CFG.COST_CRIT
    $color = $C.FG_GREEN
    $extra = ''
    if     ($ci -lt $cw) { $color = $C.FG_GREEN }
    elseif ($ci -lt $cc) { $color = $C.FG_YELLOW }
    else                 { $color = $C.FG_RED; $extra = ' !' }
    $n = 0.0
    $shown = if ([double]::TryParse([string]$Cost, [ref]$n)) {
        ('{0:F2}' -f $n)
    } else { '0.00' }
    return "$ $color$($C.BOLD)$shown$($C.RESET)$extra"
}

function Format-Remaining {
    param($ResetEpoch)
    if ($null -eq $ResetEpoch) { return '--' }
    $s = [string]$ResetEpoch
    if ([string]::IsNullOrEmpty($s)) { return '--' }
    $ep = 0.0
    if (-not [double]::TryParse($s, [ref]$ep)) { return '--' }
    if ([Math]::Floor($ep) -ne $ep -or $ep -lt 0) { return '--' }
    $ep   = [long]$ep
    $now  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = $ep - $now
    if ($diff -le 0)     { return 'reset' }
    if ($diff -ge 86400) { return ("{0}d {1}h" -f [long][Math]::Floor($diff/86400), [long][Math]::Floor(($diff%86400)/3600)) }
    if ($diff -ge 3600)  { return ("{0}h {1}m" -f [long][Math]::Floor($diff/3600),  [long][Math]::Floor(($diff%3600)/60)) }
    return ("{0}m" -f [long][Math]::Floor($diff/60))
}

function Render-Line4 {
    param($Cost, $FivePct, $FiveReset, $WeekPct, $WeekReset, [string]$VimMode)
    $costPart = Format-Cost $Cost

    $fiveRemainStr = Format-Remaining $FiveReset
    if ($null -ne $FivePct) {
        $fiveColor  = Color-ByPct ([int]$FivePct)
        $fiveBar    = Make-Bar    ([int]$FivePct)
        $fivePctStr = "$(Pad3 $FivePct)%"
    } else {
        $fiveColor  = $C.FG_MUTED
        $fiveBar    = Make-Bar 0
        $fivePctStr = ' --%'
    }
    $fiveExtra = ''
    $m = [regex]::Match($fiveRemainStr, '^(\d+)m$')
    if ($m.Success -and ([int]$m.Groups[1].Value) -le $CFG.LIMIT_WARN_MIN) { $fiveExtra = ' !' }
    $fiveRemainSeg = ''
    if ($fiveRemainStr -ne '--') {
        $fiveRemainSeg = " $($C.FG_SEP)($($C.FG_MUTED)$fiveRemainStr$fiveExtra$($C.RESET)$($C.FG_SEP))$($C.RESET)"
    }

    $weekRemainStr = Format-Remaining $WeekReset
    if ($null -ne $WeekPct) {
        $weekColor  = Color-ByPct ([int]$WeekPct)
        $weekBar    = Make-Bar    ([int]$WeekPct)
        $weekPctStr = "$(Pad3 $WeekPct)%"
    } else {
        $weekColor  = $C.FG_MUTED
        $weekBar    = Make-Bar 0
        $weekPctStr = ' --%'
    }
    $weekRemainSeg = ''
    if ($weekRemainStr -ne '--') {
        $weekRemainSeg = " $($C.FG_SEP)($($C.FG_MUTED)$weekRemainStr$($C.RESET)$($C.FG_SEP))$($C.RESET)"
    }

    $prompt = [char]0x276F
    return "$costPart$($SEP)5h $fiveBar  $fiveColor$fivePctStr$($C.RESET)$fiveRemainSeg$($SEP)Week $weekBar  $weekColor$weekPctStr$($C.RESET)$weekRemainSeg$SEP$prompt  $($C.FG_MUTED)$VimMode$($C.RESET)"
}

# ----------------------------------
# Extract - mirror jq field selection with safe defaults
# ----------------------------------
function Extract-Fields {
    param($Data)
    $cw = Get-Prop $Data 'context_window'

    $inTok  = [long](Get-Prop $cw 'total_input_tokens'  0)
    $outTok = [long](Get-Prop $cw 'total_output_tokens' 0)
    $ctxMax = [long](Get-Prop $cw 'context_window_size' 200000)
    if ($ctxMax -le 0) { $ctxMax = 200000 }
    $ctxUsed = $inTok + $outTok
    $ctxPctRaw = Get-Prop $cw 'used_percentage'
    if ($null -eq $ctxPctRaw) {
        $ctxPct = [int][Math]::Floor(($ctxUsed * 100.0) / $ctxMax)
    } else {
        $ctxPct = [int][Math]::Floor([double]$ctxPctRaw)
    }

    $rl = Get-Prop $Data 'rate_limits'
    $fh = Get-Prop $rl 'five_hour'
    $sd = Get-Prop $rl 'seven_day'

    function _PctOrNull($V) {
        if ($null -eq $V) { return $null }
        return [int][Math]::Floor([double]$V)
    }

    $model = Get-Prop (Get-Prop $Data 'model') 'display_name' 'Claude'
    $ws    = Get-Prop $Data 'workspace'
    $cwd   = Get-Prop $ws 'current_dir' '.'
    $cost  = Get-Prop (Get-Prop $Data 'cost') 'total_cost_usd' 0
    $vim   = Get-Prop (Get-Prop $Data 'vim') 'mode' 'NORMAL'
    $wt    = Get-Prop $ws 'git_worktree' ''

    return @{
        Model     = $model
        Cwd       = $cwd
        CtxUsed   = $ctxUsed
        CtxMax    = $ctxMax
        CtxPct    = $ctxPct
        Cost      = $cost
        FiveReset = (Get-Prop $fh 'resets_at' '')
        FivePct   = (_PctOrNull (Get-Prop $fh 'used_percentage'))
        WeekPct   = (_PctOrNull (Get-Prop $sd 'used_percentage'))
        WeekReset = (Get-Prop $sd 'resets_at' '')
        VimMode   = $vim
        WtName    = $wt
    }
}

# ----------------------------------
# Output - raw UTF-8 bytes to stdout (cp949-safe)
# ----------------------------------
function Write-Stdout {
    param([string]$Text)
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $stream = [Console]::OpenStandardOutput()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

# ----------------------------------
# Main - catch-all so CC never sees a half-written line on unexpected throws
# ----------------------------------
try {
    $data = Parse-Input
    $f = Extract-Fields $data

    $out = (Render-Line1 $f.Cwd) + "`n" +
           (Render-Line2 $f.Cwd $f.WtName) + "`n" +
           (Render-Line3 $f.Model $f.CtxPct $f.CtxUsed $f.CtxMax) + "`n" +
           (Render-Line4 $f.Cost $f.FivePct $f.FiveReset $f.WeekPct $f.WeekReset $f.VimMode) + "`n"

    Write-Stdout $out
} catch {
    $msg = if ($_ -and $_.Exception) { $_.Exception.Message } else { 'unknown' }
    $homeDir = $env:USERPROFILE
    if (-not [string]::IsNullOrEmpty($homeDir)) { $msg = $msg.Replace($homeDir, '~') }
    Write-Stdout ([char]0x25B8 + " (statusline error: $msg)`n")
}
