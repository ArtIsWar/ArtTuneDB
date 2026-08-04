# ============================================================================
# Install-ArtTune.ps1 -- ArtIsWar Audio Stack Installer
# ============================================================================
# Licensed under GPL-3.0 -- https://www.gnu.org/licenses/gpl-3.0.html
# ============================================================================
# Self-contained installer for the ArtIsWar audio stack.
# Three paths: Approved Device | DAC/Amp/Onboard | Uninstall
#
# Usage:  irm artiswar.io/tools/ArtTuneGuided | iex
#    or:  powershell -ExecutionPolicy Bypass -File Install-ArtTune.ps1
#
# This script does NOT configure E-APO, Voicemeeter routing, LEQ, or profiles.
# That is either manual (video guide) or automated (ArtTuneKit app).
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PS 5.1 perf: IWR progress bars tank download speed dramatically
$ProgressPreference = 'SilentlyContinue'

# .NET Framework caps outbound connections at 2 per host and the limit is read when a
# host's ServicePoint is first created, so this has to happen before any download.
# cdn.artiswar.io is the FallbackUrl for three specs, which overruns 2 as soon as a
# mirror retry fires. BITS has its own transport and is unaffected either way.
try { [System.Net.ServicePointManager]::DefaultConnectionLimit = 12 } catch { }

$script:Version = "1.2"
# Resolve 8.3 short names (e.g. LEDZIU~1) to long form for BITS compatibility
$tempParent = $env:TEMP
if (Test-Path $tempParent) { $tempParent = (Get-Item $tempParent).FullName }
$script:TempPath = Join-Path $tempParent "ArtIsWar-Setup"
$script:BoxWidth = 70
$script:ScreenWidth = 120
$script:BoxMargin = ' ' * [Math]::Floor(($script:ScreenWidth - $script:BoxWidth - 2) / 2)

$script:HiFiCableRegistryKeys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\VB:ASIOBridge {17359A74-1236-5467}",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VB:ASIOBridge {17359A74-1236-5467}",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\VB:HiFiCable {17359A74-1236-5467}",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VB:HiFiCable {17359A74-1236-5467}"
)

# Non-fatal download failures, keyed by component. Populated by Start-ParallelDownloads.
# Initialized here because Get-Downloads skips that function entirely when nothing needs
# downloading (a fully-installed re-run), and StrictMode forbids reading it unset.
$script:DownloadWarnings = @{}

# Replaced wholesale by Set-ArtTuneEndpoints. Initialized here so the completion summary
# can read .Verified even on a path where the endpoint step never ran. Verified defaults
# to $true: an endpoint step that did not run has not failed.
$script:ArtTuneEndpoints = [pscustomobject]@{ Render8 = $null; Render16 = $null; Capture = $null; Verified = $true }

# Set by Write-InitialConfig when config.txt is written with placeholder Include paths.
# Defaults to $false so a path that never wrote a config does not warn about one.
$script:ConfigIsPlaceholder = $false

# Path of the FOREIGN config.txt backup taken this run, if any. Backup-EAPOConfigFile
# is now called twice on the Install path -- once before E-APO's own setup runs (which
# can replace config.txt) and once before Write-InitialConfig overwrites it -- and only
# the first call sees the user's real file. See Backup-EAPOConfigFile.
$script:ForeignConfigBackup = $null

# Outcome of the ArtTuneKit plugin removal inside Uninstall-ExistingEAPO. A script
# variable rather than a return value: that function returns a single status string
# the caller switches on, and the plugin result is a SECOND, independent outcome --
# widening the return type would break that switch for no gain. Initialized here so
# the completion box can read it on the many paths where the plugin step never ran
# (no E-APO, so an early NotFound), which StrictMode would otherwise fault on.
#   None       - nothing to remove, or the step was never reached. Reports nothing.
#   Removed    - both folders gone.
#   SkippedATK - the ArtTuneKit app is installed and shares them. Nothing deleted.
#   Failed     - at least one folder survived; FailedPaths names the survivors.
$script:PluginRemoval = [pscustomobject]@{
    State       = 'None'
    FailedPaths = @()
}

# ---- 2026.07-Overhaul single-point configuration --------------------------
# Canonical ArtTuneDB root (E-APO config). Shared by the release extract target,
# the desktop-shortcut TargetPath, and every config.txt include.
$script:ArtTuneDBRoot = Join-Path $env:ProgramFiles "EqualizerAPO\config\ArtTuneDB"

# R2-hosted assets: endpoint icons, HRIR wavs, and the third-party installer mirror.
$script:AssetBase = "https://cdn.artiswar.io"

# R2 mirror base for the library release zip (public ArtTuneDB/ subdir).
$script:LibraryMirrorBase = "https://cdn.artiswar.io"

# ArtTuneDB library release (single zip asset) -- GitHub releases API.
$script:LibraryReleaseApi = "https://api.github.com/repos/ArtIsWar/ArtTuneDB/releases/latest"

# false = fetch library zip directly from the R2 mirror (testing / pre-release);
# flip to true once the flattened release is published to GitHub (see the flip plan).
$script:UseGitHubRelease = $false

# The flattened release zip filename; must match what is uploaded to R2 /
# published to GitHub. (During testing this is set to the random test-zip name.)
# Fallback only. The live name is derived from CDN latest-version.txt
# as "ArtTuneDB-$cdnVersion.zip"; keep this in step with the stamp in
# library/version.txt.
$script:LibraryReleaseAsset = 'ArtTuneDB-2026.07.1-Overhaul.zip'

# Anonymous setup counter endpoint. Fire-and-forget; silent on failure.
$script:SetupPingUrl = "https://artiswar.io/api/setup-ping"

# ============================================================================
# SECTION 1: Console UI Helpers
# ============================================================================

function Center-Text {
    <#
    .SYNOPSIS
        Centers text within the given width, padding both sides with spaces.
    #>
    param(
        [string]$Text,
        [int]$Width
    )
    $spaces = [Math]::Max(0, $Width - $Text.Length)
    $leftPad = [Math]::Floor($spaces / 2)
    $rightPad = $spaces - $leftPad
    return (' ' * $leftPad) + $Text + (' ' * $rightPad)
}

function Write-CenteredBlock {
    <#
    .SYNOPSIS
        Prints a block of lines centered on screen. Lines are left-aligned
        relative to each other, with the whole block centered horizontally.
    #>
    param(
        [hashtable[]]$Lines,
        [int]$ScreenWidth = $script:ScreenWidth
    )
    $maxLen = ($Lines | ForEach-Object { $_.Text.Length } | Measure-Object -Maximum).Maximum
    $margin = ' ' * [Math]::Max(0, [Math]::Floor(($ScreenWidth - $maxLen) / 2))
    foreach ($l in $Lines) {
        if ($l.ContainsKey('NoNewline') -and $l.NoNewline) {
            Write-Host "$margin$($l.Text)" -ForegroundColor $l.Color -NoNewline
        } else {
            Write-Host "$margin$($l.Text)" -ForegroundColor $l.Color
        }
    }
    return $margin
}

function Write-Banner {
    <#
    .SYNOPSIS
        Displays the Art Tune installer title banner with version info.
    #>
    $w = 70
    $border = [string]::new([char]0x2550, $w)
    $L = [char]0x2551   # left/right border char
    $blank = ' ' * $w
    # Center the box itself on a 120-column screen
    $m = ' ' * [Math]::Floor(($script:ScreenWidth - $w - 2) / 2)

    Write-Host ""
    Write-Host "$m$([char]0x2554)$border$([char]0x2557)" -ForegroundColor Yellow
    Write-Host "$m$L$(Center-Text 'Art Tune Manual Installer' $w)$L" -ForegroundColor Yellow
    Write-Host "$m$L$(Center-Text 'updated Jul 2026' $w)$L" -ForegroundColor Yellow
    Write-Host "$m$L$(Center-Text "artiswar.io  $([char]0x2022)  v$script:Version" $w)$L" -ForegroundColor Yellow
    Write-Host "$m$L$blank$L" -ForegroundColor Yellow
    # YouTube line (Cyan interior, Yellow borders)
    Write-Host "$m$L" -ForegroundColor Yellow -NoNewline
    Write-Host "$(Center-Text 'Free Video Guide: youtube.com/artiswar' $w)" -ForegroundColor Cyan -NoNewline
    Write-Host "$L" -ForegroundColor Yellow
    # License line (DarkGray interior)
    Write-Host "$m$L" -ForegroundColor Yellow -NoNewline
    Write-Host "$(Center-Text 'Licensed under GPL-3.0' $w)" -ForegroundColor DarkGray -NoNewline
    Write-Host "$L" -ForegroundColor Yellow
    Write-Host "$m$L$blank$L" -ForegroundColor Yellow
    # Release note (DarkGray, 2 lines)
    Write-Host "$m$L" -ForegroundColor Yellow -NoNewline
    Write-Host "$(Center-Text 'Guided Install: VB-CABLE + E-APO audio stack.' $w)" -ForegroundColor DarkGray -NoNewline
    Write-Host "$L" -ForegroundColor Yellow
    Write-Host "$m$L" -ForegroundColor Yellow -NoNewline
    Write-Host "$(Center-Text '2026.07 Overhaul: 16-channel spatial + auto library.' $w)" -ForegroundColor DarkGray -NoNewline
    Write-Host "$L" -ForegroundColor Yellow
    Write-Host "$m$([char]0x255A)$border$([char]0x255D)" -ForegroundColor Yellow
    Write-Host ""
}

function Write-ActionBox {
    <#
    .SYNOPSIS
        Draws a bordered action-required prompt and waits for Enter.
    #>
    param(
        [string[]]$Lines
    )

    $maxLen = ($Lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $width = [Math]::Max($maxLen + 4, $script:BoxWidth)
    $border = [string]::new([char]0x2550, $width)
    $L = [char]0x2551

    $m = $script:BoxMargin

    Write-Host ""
    Write-Host "$m$([char]0x2554)$border$([char]0x2557)" -ForegroundColor Yellow
    Write-Host "$m$L$(Center-Text 'ACTION REQUIRED' $width)$L" -ForegroundColor Yellow
    Write-Host "$m$L$(' ' * $width)$L" -ForegroundColor Yellow
    foreach ($line in $Lines) {
        Write-Host "$m$L" -ForegroundColor Yellow -NoNewline
        Write-Host "  $line" -NoNewline
        Write-Host "$(' ' * [Math]::Max(0, $width - $line.Length - 2))$L" -ForegroundColor Yellow
    }
    Write-Host "$m$L$(' ' * $width)$L" -ForegroundColor Yellow
    Write-Host "$m$L$(Center-Text 'Press Enter when ready...' $width)$L" -ForegroundColor Yellow
    Write-Host "$m$([char]0x255A)$border$([char]0x255D)" -ForegroundColor Yellow
    Write-Host ""

    Read-Host | Out-Null

    # Instant feedback so the user knows we received the input (no "hang" feeling)
    $frames = @('|','/','-','\')
    for ($i = 0; $i -lt 6; $i++) {
        $frame = $frames[$i % $frames.Count]
        Write-Host "`r$m$frame Working..." -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 120
    }
    Write-Host "`r$m$([char]0x2713) Got it, continuing...          " -ForegroundColor Green
}

function Get-ProgressBar {
    <#
    .SYNOPSIS
        Returns an ASCII progress bar string.
        Percentage mode: filled proportional bar.  Pulse mode: bouncing animation.
    .PARAMETER Width
        Total inner width of the bar (between the brackets).
    .PARAMETER Percent
        0-100 for a determinate bar.  -1 for indeterminate pulse.
    .PARAMETER Frame
        Frame counter driving the pulse animation.
    #>
    param(
        [int]$Width = 28,
        [int]$Percent = -1,
        [int]$Frame = 0
    )
    if ($Percent -ge 0) {
        $filled = [Math]::Floor($Width * [Math]::Min($Percent, 100) / 100)
        if ($filled -ge $Width) {
            $bar = "=" * $Width
        } elseif ($filled -gt 0) {
            $bar = ("=" * ($filled - 1)) + ">"
        } else {
            $bar = ""
        }
        return "[" + $bar.PadRight($Width) + "]"
    }
    # Indeterminate pulse: 5-char slug bouncing left-to-right
    $slug = 5
    $travel = $Width - $slug
    if ($travel -lt 1) { $travel = 1 }
    $pos = $Frame % ($travel * 2)
    if ($pos -ge $travel) { $pos = $travel * 2 - $pos }
    $inner = (" " * $pos) + ("=" * ($slug - 1)) + ">" + (" " * [Math]::Max(0, $Width - $pos - $slug))
    return "[" + $inner.Substring(0, $Width) + "]"
}

function Format-ByteSize {
    <#
    .SYNOPSIS
        Formats a byte count as "12.3 MB" / "482 KB", or "" below 1 KB.
    .PARAMETER Bracket
        Wrap the result in square brackets, matching the download tally's "[12.3 MB]".
        Sub-1-KB still returns "" so the caller emits nothing rather than "[]".
    #>
    param(
        [long]$Bytes,
        [switch]$Bracket
    )
    $s = ""
    if ($Bytes -ge 1MB) { $s = "{0:N1} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { $s = "{0:N0} KB" -f ($Bytes / 1KB) }
    if ($Bracket -and $s) { return "[$s]" }
    return $s
}

function Format-Duration {
    <#
    .SYNOPSIS
        Formats a span of seconds as m:ss, clamped so a nonsense ETA cannot widen the row.
    #>
    param([double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $t = [int][Math]::Round($Seconds)
    if ($t -ge 6000) { return "99:59+" }
    return "{0}:{1:00}" -f [int]($t / 60), ($t % 60)
}

function Get-ConsolePaint {
    <#
    .SYNOPSIS
        Probes whether this host supports absolute cursor positioning, and returns the
        safe paint width. Enabled = $false means the caller must use the single-line
        `r renderer instead -- i.e. exactly the behaviour that shipped before.
    .DESCRIPTION
        Allowlist, not denylist: only the real console host is known to honour
        RawUI.CursorPosition. The ISE setter throws, VS Code's is a silent no-op that
        would scroll painted rows away, and a redirected stream has no cursor at all.
        Anything unrecognised degrades instead of corrupting the display.

        Width comes from BufferSize (not WindowSize, not $script:ScreenWidth) because
        the buffer is what governs wrapping, and one column is held back so a full-width
        row cannot trip conhost's delayed-wrap flag.
    #>
    $result = @{ Enabled = $false; Width = $script:ScreenWidth - 1 }
    if ("$($Host.Name)" -ne 'ConsoleHost') { return $result }
    try { if ([Console]::IsOutputRedirected) { return $result } } catch { }
    try {
        $rui = $Host.UI.RawUI
        $pos = $rui.CursorPosition
        $rui.CursorPosition = $pos     # the write must round-trip, not just the read
        $w = $rui.BufferSize.Width
        if ($w -lt 40) { return $result }
        $result.Enabled = $true
        $result.Width = $w - 1
    } catch { }
    return $result
}

function Write-BlockLines {
    <#
    .SYNOPSIS
        Repaints an N-line block in place and restores the cursor.
        Returns $false if the host refused, in which case the caller must stop painting.
    .DESCRIPTION
        The block is assumed to occupy the N console rows immediately ABOVE the current
        cursor row. That top row is re-derived from the CURRENT cursor on every call, so
        console scrolling cannot invalidate it -- there is deliberately no saved absolute
        coordinate anywhere.
    .PARAMETER Cache
        Optional array of length N, mutated in place. Rows whose text and colour are
        unchanged since the last call are skipped, which stops completed rows flickering.
    #>
    param(
        [string[]]$Lines,
        [string[]]$Colors,
        [int]$Width,
        [string[]]$Cache = $null
    )
    $n = $Lines.Count
    if ($n -eq 0 -or $Colors.Count -ne $n) { return $false }
    try {
        $rui = $Host.UI.RawUI
        $anchor = $rui.CursorPosition          # struct copy, safe to restore
        $topY = $anchor.Y - $n
        if ($topY -lt 0) { return $false }
        $useCache = ($null -ne $Cache -and $Cache.Count -eq $n)
        for ($r = 0; $r -lt $n; $r++) {
            $txt = $Lines[$r]
            if ($txt.Length -gt $Width) { $txt = $txt.Substring(0, $Width) }
            else { $txt = $txt.PadRight($Width) }
            $sig = $Colors[$r] + '|' + $txt
            if ($useCache -and $Cache[$r] -eq $sig) { continue }
            $pos = $rui.CursorPosition
            $pos.X = 0
            $pos.Y = $topY + $r
            $rui.CursorPosition = $pos
            Write-Host $txt -NoNewline -ForegroundColor $Colors[$r]
            if ($useCache) { $Cache[$r] = $sig }
        }
        $rui.CursorPosition = $anchor
        return $true
    } catch {
        return $false
    }
}

function Write-Wait {
    <#
    .SYNOPSIS
        Shows a spinner while a process or condition is pending.
        Overwrites the same line to avoid scroll spam.
        Optional -Progress scriptblock returns a suffix string (e.g. "[3.2 MB]", "[45%]").
    #>
    param(
        [string]$Message,
        [scriptblock]$Until,
        [int]$TimeoutSeconds = 60,
        [scriptblock]$Progress = $null
    )

    $m = $script:BoxMargin
    $frames = @('|','/','-','\')
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $i = 0
    $pad = $script:ScreenWidth
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $frame = $frames[$i % $frames.Count]
        $suffix = ""
        if ($Progress) { $suffix = " $(& $Progress)" }
        $bar = Get-ProgressBar -Width 20 -Percent -1 -Frame $i
        $line = "$m$frame $Message $bar$suffix"
        Write-Host "`r$($line.PadRight($pad))" -NoNewline -ForegroundColor DarkGray
        if (& $Until) {
            $doneBar = Get-ProgressBar -Width 20 -Percent 100
            $doneLine = "$m$([char]0x2713) $Message $doneBar$suffix"
            Write-Host "`r$($doneLine.PadRight($pad))" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Milliseconds 200
        $i++
    }
    Write-Host "`r$m! $Message (timed out)".PadRight($pad) -ForegroundColor Yellow
    return $false
}

function Write-Completion {
    <#
    .SYNOPSIS
        PATH B completion box -- full DAC/amp/onboard install.
    #>
    param(
        [bool]$SoundControlInstalled = $true,
        [bool]$VoicemeeterInstalled = $true,
        [bool]$VBCableInstalled = $true,
        [bool]$ReaPlugsInstalled = $true,
        [bool]$EapoInstalled = $true,
        [bool]$HeSuViInstalled = $true,
        [bool]$JsfxInstalled = $true,
        [bool]$EndpointsVerified = $true,
        [bool]$ConfigIsPlaceholder = $false
    )
    $w = $script:BoxWidth
    $m = $script:BoxMargin
    $b = [string]::new([char]0x2550, $w)
    $s = [string]::new([char]0x2500, $w - 4)
    $p = { param($t) "$($script:BoxMargin)$([char]0x2551)  $t$(' ' * [Math]::Max(0, $w - $t.Length - 2))$([char]0x2551)" }

    Write-Host ""
    Write-Host "$m$([char]0x2554)$b$([char]0x2557)" -ForegroundColor Green
    Write-Host "$m$([char]0x2551)$(Center-Text "$([char]0x2713)  SETUP COMPLETE" $w)$([char]0x2551)" -ForegroundColor Green
    Write-Host "$m$([char]0x2560)$b$([char]0x2563)" -ForegroundColor Green
    # Per-component marker, following the precedent the LEQ row already set: [!] takes the
    # tick's place inline and the $p pad absorbs the width difference. A row goes Yellow
    # only when something on it needs attention, so an all-good box renders as it did
    # before (no explicit colour, host default).
    $tick = "$([char]0x2713)"
    $mk = { param($ok) if ($ok) { $tick } else { '[!]' } }
    $row = {
        param($text, [bool[]]$flags)
        if ($flags -contains $false) { Write-Host (& $p $text) -ForegroundColor Yellow }
        else { Write-Host (& $p $text) }
    }

    Write-Host (& $p "")
    Write-Host (& $p "Installed:")
    & $row "  $(& $mk $VBCableInstalled) VB-CABLE          $(& $mk $ReaPlugsInstalled) ReaPlugs" @($VBCableInstalled, $ReaPlugsInstalled)
    if ($VoicemeeterInstalled) {
        & $row "  $tick Voicemeeter       $(& $mk $EapoInstalled) E-APO" @($EapoInstalled)
    } else {
        & $row "  $(& $mk $EapoInstalled) E-APO" @($EapoInstalled)
    }
    if ($SoundControlInstalled) {
        & $row "  $(& $mk $HeSuViInstalled) HeSuVi            $tick LEQ Control Panel" @($HeSuViInstalled)
    } else {
        & $row "  $(& $mk $HeSuViInstalled) HeSuVi            [!] LEQ Control Panel" @($false)
        Write-Host (& $p "                         (download from GitHub)") -ForegroundColor Yellow
    }
    & $row "  $(& $mk $JsfxInstalled) JSFX Plugins" @($JsfxInstalled)

    # Action-required states. Printed only when they apply, so a clean run and a future
    # preset-profile path both render without them.
    if (-not $EndpointsVerified) {
        Write-Host (& $p "  [!] Audio endpoint names") -ForegroundColor Yellow
        Write-Host (& $p "      (re-run Setup, or rename in Sound settings)") -ForegroundColor Yellow
    }
    if ($ConfigIsPlaceholder) {
        Write-Host (& $p "  [!] Config not set") -ForegroundColor Yellow
        Write-Host (& $p "      (open config.txt and choose your game and version)") -ForegroundColor Yellow
    }
    Write-Host (& $p "")
    Write-Host (& $p $s) -ForegroundColor DarkGray
    Write-Host (& $p "")
    Write-Host (& $p "Press [s] below to launch LEQ Control Panel")
    Write-Host (& $p "and Device Selector, then follow the video.")
    Write-Host (& $p "")
    if ($VoicemeeterInstalled) {
        Write-Host (& $p "You can remove Voicemeeter later if you")
        Write-Host (& $p "do not need it.")
        Write-Host (& $p "")
    }
    Write-Host (& $p "Press [b] for ArtTuneKit - automated setup,") -ForegroundColor DarkGray
    Write-Host (& $p "auto-updating, with my own Voicemeeter") -ForegroundColor DarkGray
    Write-Host (& $p "replacement built in.") -ForegroundColor DarkGray
    Write-Host (& $p "")
    Write-Host "$m$([char]0x255A)$b$([char]0x255D)" -ForegroundColor Green
    Write-Host ""

    # Interactive launch options (loops until quit or back)
    while ($true) {
        $menuMargin = Write-CenteredBlock @(
            @{ Text = '[s] Open LEQ Control Panel'; Color = 'White' }
            @{ Text = '[b] ArtTuneKit - automated, auto-updating, no Voicemeeter'; Color = 'DarkGray' }
            @{ Text = '[m] Back to main menu'; Color = 'DarkGray' }
            @{ Text = '[q] Quit'; Color = 'DarkGray' }
        )
        Write-Host ""

        Write-Host "$menuMargin" -NoNewline
        Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
        $key = Read-Host
        switch ($key.ToLower()) {
            's' {
                $scExe = Join-Path $env:LOCALAPPDATA "Programs\LEQControlPanel\LEQControlPanel.exe"
                if (Test-Path $scExe) {
                    Start-Process $scExe
                    Write-Host "$($script:BoxMargin)Launched LEQ Control Panel." -ForegroundColor Green
                } else {
                    Write-Host "$($script:BoxMargin)LEQ Control Panel not found. Download it from:" -ForegroundColor Yellow
                    Write-Host "$($script:BoxMargin)https://github.com/ArtIsWar/LEQControlPanel/releases" -ForegroundColor Yellow
                }
                Write-Host ""
            }
            'b' {
                Start-Process "https://artiswar.io/arttunekit"
                Write-Host "$($script:BoxMargin)Opened in browser." -ForegroundColor Green
                Write-Host ""
            }
            'm' { return 'mainMenu' }
            'q' { return 'quit' }
            default { Write-Host "$($script:BoxMargin)Invalid choice." -ForegroundColor Red; Write-Host "" }
        }
    }
}

function Write-UninstallCompletion {
    <#
    .SYNOPSIS
        PATH C completion box -- uninstall.
    #>
    param(
        [string[]]$RemovedComponents,
        [string[]]$KeptComponents,
        [string[]]$RemovedShortcuts,
        [string[]]$FailedShortcuts
    )

    $w = $script:BoxWidth
    $m = $script:BoxMargin
    $b = [string]::new([char]0x2550, $w)
    $p = { param($t) "$($script:BoxMargin)$([char]0x2551)  $t$(' ' * [Math]::Max(0, $w - $t.Length - 2))$([char]0x2551)" }

    Write-Host ""
    Write-Host "$m$([char]0x2554)$b$([char]0x2557)" -ForegroundColor Green
    Write-Host "$m$([char]0x2551)$(Center-Text "$([char]0x2713)  UNINSTALL COMPLETE" $w)$([char]0x2551)" -ForegroundColor Green
    Write-Host "$m$([char]0x2560)$b$([char]0x2563)" -ForegroundColor Green
    Write-Host (& $p "")
    Write-Host (& $p "Removed:")
    foreach ($comp in $RemovedComponents) {
        Write-Host (& $p "  $([char]0x2713) $comp")
    }
    # The plugin outcome rides $script:PluginRemoval rather than $RemovedComponents.
    # That array also drives the caller's "restart to clear removed drivers" prompt,
    # and a plugin-only removal involves no driver.
    if ($script:PluginRemoval.State -eq 'Removed') {
        Write-Host (& $p "  $([char]0x2713) ArtTuneKit plugins (VST + JSFX)")
    }
    # Same reasoning as the plugins above: listed here rather than folded into
    # $RemovedComponents, which also drives the caller's "restart to clear removed
    # drivers" prompt -- a deleted .lnk is not a driver and must not ask for one.
    foreach ($sc in $RemovedShortcuts) {
        Write-Host (& $p "  $([char]0x2713) $sc")
    }
    # Anything deliberately left behind is stated, so "uninstall everything" does
    # not imply something was removed when it was not.
    if ($KeptComponents -and $KeptComponents.Count -gt 0) {
        Write-Host (& $p "")
        Write-Host (& $p "Kept (not installed by ArtTune):")
        foreach ($comp in $KeptComponents) {
            Write-Host (& $p "  - $comp")
        }
    }
    # Kept for a different reason than $KeptComponents: those were never ours to
    # remove, these are ours but shared with the app, so they get their own block
    # rather than being folded under "not installed by ArtTune".
    if ($script:PluginRemoval.State -eq 'SkippedATK') {
        Write-Host (& $p "")
        Write-Host (& $p "ArtTuneKit plugins kept:")
        Write-Host (& $p "  - The ArtTuneKit app is installed and")
        Write-Host (& $p "    shares them. Uninstall ArtTuneKit")
        Write-Host (& $p "    from the app to remove them.")
    }
    if ($script:PluginRemoval.State -eq 'Failed') {
        Write-Host (& $p "")
        Write-Host (& $p "Could not remove the ArtTuneKit plugins:") -ForegroundColor Yellow
        foreach ($pluginDir in $script:PluginRemoval.FailedPaths) {
            Write-Host (& $p "  $pluginDir") -ForegroundColor Yellow
        }
        Write-Host (& $p "  Restart, then re-run setup and choose") -ForegroundColor Yellow
        Write-Host (& $p "  [4] to finish removing them.") -ForegroundColor Yellow
    }
    if ($FailedShortcuts -and $FailedShortcuts.Count -gt 0) {
        Write-Host (& $p "")
        Write-Host (& $p "Could not delete these desktop icons:") -ForegroundColor Yellow
        foreach ($sc in $FailedShortcuts) {
            Write-Host (& $p "  $(Split-Path $sc -Leaf)") -ForegroundColor Yellow
        }
        Write-Host (& $p "  Delete them by hand -- they point at") -ForegroundColor Yellow
        Write-Host (& $p "  folders that no longer exist.") -ForegroundColor Yellow
    }
    Write-Host (& $p "")
    # Nothing on any uninstall path writes the MMDevices names or icons back --
    # Set-ArtTuneEndpoints only ever writes them, and the original names are not
    # saved anywhere to restore from. The hedge is load-bearing: a successful
    # VB-CABLE or Voicemeeter removal takes its endpoints with the driver, but a
    # Failed or NotFound one leaves them renamed and on screen. Normal Audio and
    # Virtual Mix are the Voicemeeter pair, written only on a Standard install.
    Write-Host (& $p "Any device still named Art Tune, Normal")
    Write-Host (& $p "Audio or Virtual Mix keeps that name and")
    Write-Host (& $p "icon. Setup does not rename it back. You")
    Write-Host (& $p "can rename it in Windows Sound settings.")
    Write-Host (& $p "")
    Write-Host (& $p "You may also need to set your Windows")
    Write-Host (& $p "default audio device back to your")
    Write-Host (& $p "headphones/DAC.")
    Write-Host (& $p "")
    Write-Host "$m$([char]0x255A)$b$([char]0x255D)" -ForegroundColor Green
    Write-Host ""
}

function Show-ThankYou {
    <#
    .SYNOPSIS
        Displays a credits/thank-you list with links to each developer's page.
    #>
    $w = $script:BoxWidth
    $m = $script:BoxMargin
    $b = [string]::new([char]0x2550, $w)
    $p = { param($t) "$($script:BoxMargin)$([char]0x2551)  $t$(' ' * [Math]::Max(0, $w - $t.Length - 2))$([char]0x2551)" }

    $credits = @(
        @{ Num = '1'; Tool = 'Voicemeeter + VB-CABLE'; Dev = 'Vincent Burel (VB-Audio)'; Url = 'https://shop.vb-audio.com' }
        @{ Num = '2'; Tool = 'ReaPlugs';                  Dev = 'Cockos Inc';               Url = 'https://www.reaper.fm/reaplugs/' }
        @{ Num = '3'; Tool = 'Equalizer APO';             Dev = 'Jonas Thedering';           Url = 'https://sourceforge.net/projects/equalizerapo/' }
        @{ Num = '4'; Tool = 'HeSuVi';                    Dev = 'jak33';                     Url = 'https://sourceforge.net/projects/hesuvi/' }
        @{ Num = '5'; Tool = 'Squig.link';                Dev = 'GadgetryTech';              Url = 'https://www.youtube.com/gadgetrytech' }
        @{ Num = '6'; Tool = 'Install-ArtTune.ps1 + LEQ'; Dev = 'ArtIsWar';                  Url = 'https://artiswar.io' }
    )

    Write-Host ""
    Write-Host "$m$([char]0x2554)$b$([char]0x2557)" -ForegroundColor Yellow
    Write-Host "$m$([char]0x2551)$(Center-Text 'Thank You' $w)$([char]0x2551)" -ForegroundColor Yellow
    Write-Host "$m$([char]0x2560)$b$([char]0x2563)" -ForegroundColor Yellow
    Write-Host (& $p "")
    Write-Host (& $p "This installer depends on tools built by")
    Write-Host (& $p "talented developers. Show them some love:")
    Write-Host (& $p "")
    foreach ($c in $credits) {
        $line = "[$($c.Num)] $($c.Tool) - $($c.Dev)"
        if ($c.Num -eq '6') {
            Write-Host (& $p $line) -ForegroundColor DarkGray
        } else {
            Write-Host (& $p $line)
        }
    }
    Write-Host (& $p "")
    Write-Host "$m$([char]0x255A)$b$([char]0x255D)" -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        $menuMargin = Write-CenteredBlock @(
            @{ Text = '[1-6] Open developer page'; Color = 'White' }
            @{ Text = '[m] Back to main menu'; Color = 'DarkGray' }
            @{ Text = '[q] Quit'; Color = 'DarkGray' }
        )
        Write-Host ""
        Write-Host "$menuMargin" -NoNewline
        Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
        $key = Read-Host
        $num = 0
        if ([int]::TryParse($key, [ref]$num) -and $num -ge 1 -and $num -le 6) {
            $selected = $credits[$num - 1]
            Start-Process $selected.Url
            Write-Host "$($script:BoxMargin)Opened $($selected.Dev) in browser." -ForegroundColor Green
            Write-Host ""
        }
        elseif ($key -eq 'm' -or $key -eq 'M') { return 'mainMenu' }
        elseif ($key -eq 'q' -or $key -eq 'Q') { return 'quit' }
        else {
            Write-Host "$($script:BoxMargin)Invalid choice." -ForegroundColor Red
            Write-Host ""
        }
    }
}

# ============================================================================
# SECTION 2: Utility Functions
# ============================================================================

# ---- Culture-invariant identity matching -----------------------------------
# PowerShell's -match, -notmatch, -like and -notlike fold case using the CURRENT
# CULTURE. Turkish and Azeri lowercase 'I' to the dotless 'i', so on those locales:
#
#     'VB-AUDIO HI-FI CABLE' -like '*Hi-Fi*'   ->  False
#     'VB:ASIO BRIDGE'       -match 'ASIO Bridge' -> False
#
# Every identity token this script matches on -- Hi-Fi, HiFi, hfvaio, VB-Audio,
# Wave Link, Elgato Virtual, Voicemeeter, ASIO Bridge -- contains an i, and the
# real values arrive uppercased from CIM/registry/pnputil. So on a tr-TR box the
# raw operators silently stop matching.
#
# The worst consequence is not a missed detection. Uninstall-ExistingHiFiCable
# detects via literal registry paths (Test-Path, unaffected) but VERIFIES with the
# device-name match -- so it would clean the registry, no-op every driver-store arm,
# find nothing in the verify pass and report 'Removed' for a driver still installed.
# That is a false verified-removed, the same defect ArtTuneKit hit in the field.
#
# Use these two for identity tokens. String -eq/-ne need NO conversion: PowerShell
# compares strings ordinally, so 'I' -eq 'i' is True even under tr-TR (which is why
# Get-ArtTuneEndpoints' -ne 'VB-Audio Virtual Cable' was never exposed).
$script:OrdinalRegexOptions = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase,CultureInvariant'

function Test-OrdinalMatch {
    <#
    .SYNOPSIS
        Culture-invariant, case-insensitive regex test. The -match replacement.
    #>
    param([string]$Text, [string]$Pattern)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    return [regex]::IsMatch($Text, $Pattern, $script:OrdinalRegexOptions)
}

function Test-OrdinalContains {
    <#
    .SYNOPSIS
        Culture-invariant, case-insensitive substring test. The -like "*x*" replacement.
        Uses IndexOf because String.Contains(string, StringComparison) does not exist
        on the .NET Framework build of PowerShell 5.1 that this script runs under.
    #>
    param([string]$Text, [string]$Needle)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    return ($Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-OrdinalMatchGroup {
    <#
    .SYNOPSIS
        Culture-invariant capture-group read. The "$x -match p; $Matches[1]" replacement.
        Returns '' when the pattern does not match.
    #>
    param([string]$Text, [string]$Pattern, [int]$Group = 1)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $m = [regex]::Match($Text, $Pattern, $script:OrdinalRegexOptions)
    if (-not $m.Success) { return '' }
    return $m.Groups[$Group].Value
}

function Send-SetupPing {
    <#
    .SYNOPSIS
        Fire-and-forget anonymous setup counter. Called on SUCCESSFUL setup
        completion only. Silent on any failure; never blocks completion beyond a
        short timeout. Sends a mode flag and a SHA-256 hash of the machine GUID
        (never the raw GUID).
    #>
    param([Parameter(Mandatory)][string]$Mode)

    Write-Host ""
    Write-Host "$($script:BoxMargin)Reporting anonymous setup count..." -ForegroundColor DarkGray -NoNewline
    try {
        $raw = ''
        try { $raw = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid } catch { $raw = '' }
        $machineId = ''
        if ($raw) {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$raw))
                $machineId = -join ($hash | ForEach-Object { $_.ToString('x2') })
            } finally { $sha.Dispose() }
        }
        $body = @{ mode = $Mode; machineId = $machineId } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $script:SetupPingUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 3 -ErrorAction Stop | Out-Null
        Write-Host " done." -ForegroundColor DarkGray
    } catch {
        # Silent: the counter must never affect setup success.
        Write-Host " skipped." -ForegroundColor DarkGray
    }
}

function Test-AdminPrivilege {
    <#
    .SYNOPSIS
        Verifies the script is running with administrator privileges.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ""
        Write-Host "$($script:BoxMargin)ERROR: This script must be run as Administrator." -ForegroundColor Red
        Write-Host ""
        Write-Host "$($script:BoxMargin)Right-click PowerShell and select 'Run as administrator'," -ForegroundColor White
        Write-Host "$($script:BoxMargin)then run this script again." -ForegroundColor White
        Write-Host ""
        exit 1
    }
}

function Test-SystemCompatibility {
    <#
    .SYNOPSIS
        Checks for ARM64 architecture and Windows S Mode.
    #>
    # ARM64 check
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        if ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)ERROR: ARM64 devices are not supported." -ForegroundColor Red
            Write-Host "$($script:BoxMargin)The audio stack requires an x64 processor." -ForegroundColor White
            Write-Host ""
            exit 1
        }
    } catch {
        # RuntimeInformation not available on very old PS -- skip
    }

    # S Mode check
    try {
        $ciPolicy = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -ErrorAction SilentlyContinue
        if ($ciPolicy -and $ciPolicy.SkuPolicyRequired -eq 1) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)ERROR: Windows is in S Mode." -ForegroundColor Red
            Write-Host "$($script:BoxMargin)S Mode blocks third-party software installation." -ForegroundColor White
            Write-Host "$($script:BoxMargin)Switch out of S Mode in Settings > Update & Security > Activation." -ForegroundColor White
            Write-Host ""
            exit 1
        }
    } catch {
        # Registry key may not exist -- not S Mode
    }
}

function Test-PowerShellEdition {
    <#
    .SYNOPSIS
        Refuses to run under PowerShell Core.
    .DESCRIPTION
        Setup depends on Start-BitsTransfer (SourceForge downloads), Get-AppxPackage
        (Wave Link 3 detection) and Get-PnpDevice, none of which load natively in
        PowerShell 7. Without this guard the failures are partial and silent: the
        Get-AppxPackage failure in particular is swallowed, Wave Link goes undetected,
        and the user is offered a Voicemeeter they do not want.

        No #Requires at the top of the file: this script is delivered via
        'irm ... | iex', where a #Requires failure is opaque.
    #>
    # PSEdition is absent before 5.1; ContainsKey keeps that read StrictMode-safe.
    $edition = 'Desktop'
    if ($PSVersionTable.ContainsKey('PSEdition')) { $edition = "$($PSVersionTable.PSEdition)" }

    if ($edition -ne 'Desktop') {
        Write-Host ""
        Write-Host "$($script:BoxMargin)ERROR: This installer requires Windows PowerShell 5.1." -ForegroundColor Red
        Write-Host "$($script:BoxMargin)You are running PowerShell $($PSVersionTable.PSVersion) ($edition), which" -ForegroundColor White
        Write-Host "$($script:BoxMargin)cannot load the BITS, AppX and PnP components setup needs." -ForegroundColor White
        Write-Host "$($script:BoxMargin)Open 'Windows PowerShell' as Administrator and run it again." -ForegroundColor White
        Write-Host ""
        exit 1
    }
}

function Initialize-NativeMethods {
    <#
    .SYNOPSIS
        Loads P/Invoke signatures for window management.
    #>
    if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class NativeMethods {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
'@
    }
}

function Set-WindowForeground {
    <#
    .SYNOPSIS
        Brings a process's main window to the foreground.
    #>
    param([System.Diagnostics.Process]$Process)
    try {
        Initialize-NativeMethods
        # Wait for window handle to appear
        for ($i = 0; $i -lt 20; $i++) {
            $Process.Refresh()
            if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
                [NativeMethods]::ShowWindow($Process.MainWindowHandle, 5) | Out-Null  # SW_SHOW
                [NativeMethods]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
                return
            }
            Start-Sleep -Milliseconds 250
        }
    } catch { } # Window focus is best-effort; failure is non-fatal
}

function Stop-AudioHoldingProcesses {
    <#
    .SYNOPSIS
        Stops Voicemeeter processes so the uninstaller can run cleanly.
    #>
    $vmNames = @('voicemeeter','voicemeeter_x64','voicemeeterpro','voicemeeterpro_x64',
                 'voicemeeter8','voicemeeter8x64','audiorepeater','audiorepeater_x64')

    $procs = @(Get-Process -Name $vmNames -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return }

    Write-Host "$($script:BoxMargin)Stopping Voicemeeter ($($procs.Count) process(es))..." -ForegroundColor DarkGray
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    $null = Write-Wait -Message "Waiting for Voicemeeter to exit" -Until {
        @(Get-Process -Name $vmNames -ErrorAction SilentlyContinue).Count -eq 0
    } -TimeoutSeconds 10
    Start-Sleep -Milliseconds 500
}

function Stop-EAPOEcosystemProcesses {
    <#
    .SYNOPSIS
        Stops Peace, HeSuVi, and E-APO GUI tools so their file locks
        on E-APO DLLs are released before uninstall / folder deletion.
    #>
    $eapoPath = Join-Path $env:ProgramFiles "EqualizerAPO"

    # Processes with unique names -- safe to kill by name alone
    $safeNames = @('Peace', 'HeSuVi', 'Configurator', 'DeviceSelector')

    $killed = @()

    foreach ($name in $safeNames) {
        $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if ($procs.Count -gt 0) {
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            $killed += $name
        }
    }

    # Editor.exe is too generic to kill by name -- filter by E-APO path
    $editorProcs = @(Get-Process -Name 'Editor' -ErrorAction SilentlyContinue |
        Where-Object {
            try { $_.Path -and $_.Path.StartsWith($eapoPath, [System.StringComparison]::OrdinalIgnoreCase) }
            catch { $false }
        })
    if ($editorProcs.Count -gt 0) {
        $editorProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        $killed += 'Editor'
    }

    if ($killed.Count -eq 0) { return }

    Write-Host "$($script:BoxMargin)Stopped E-APO ecosystem processes: $($killed -join ', ')" -ForegroundColor DarkGray

    $null = Write-Wait -Message "Waiting for E-APO ecosystem processes to exit" -Until {
        $remaining = @(Get-Process -Name $safeNames -ErrorAction SilentlyContinue).Count
        $remaining += @(Get-Process -Name 'Editor' -ErrorAction SilentlyContinue |
            Where-Object {
                try { $_.Path -and $_.Path.StartsWith($eapoPath, [System.StringComparison]::OrdinalIgnoreCase) }
                catch { $false }
            }).Count
        $remaining -eq 0
    } -TimeoutSeconds 10

    Start-Sleep -Milliseconds 500
}

# ============================================================================
# SECTION 3: Download Functions
# ============================================================================

$script:BitsOriginalStartType = $null
$script:BitsWasRunning        = $true

function Ensure-BitsRunning {
    $svc = Get-Service -Name 'BITS' -ErrorAction Stop
    $script:BitsOriginalStartType = $svc.StartType
    $script:BitsWasRunning = ($svc.Status -eq 'Running')

    if ($script:BitsWasRunning) { return }

    if ($svc.StartType -eq 'Disabled') {
        Set-Service -Name 'BITS' -StartupType Manual -ErrorAction Stop
    }
    Start-Service -Name 'BITS' -ErrorAction Stop
}

function Restore-BitsState {
    if ($null -eq $script:BitsOriginalStartType) { return }
    if ($script:BitsWasRunning) { return }
    try {
        Stop-Service -Name 'BITS' -Force -ErrorAction SilentlyContinue
        if ($script:BitsOriginalStartType -eq 'Disabled') {
            Set-Service -Name 'BITS' -StartupType Disabled -ErrorAction SilentlyContinue
        }
    } catch { }
}

$script:SourceForgeMirrors = @(
    "",                          # Default (let SourceForge pick)
    "?use_mirror=autoselect",    # Force autoselect
    "?use_mirror=netcologne",    # Germany
    "?use_mirror=deac-riga",     # Latvia
    "?use_mirror=kent",          # UK
    "?use_mirror=cfhcable"       # US
)

# NOT WIRED UP, deliberately. E-APO is pinned to the CDN copy of 1.4.2 (see its spec in
# Get-Downloads), which is the build ArtTuneKit bundles and the library configs were
# validated against. This resolver is kept, not deleted, because it is the whole of the
# "go back to whatever SourceForge calls latest" path: set the EAPO spec's UrlResolver
# to this and drop its Url, and the old behaviour returns. Do not delete it as dead code.
$script:EapoUrlResolver = {
    $fallback = "https://sourceforge.net/projects/equalizerapo/files/1.4/EqualizerAPO64-1.4.exe/download"
    $ProgressPreference = 'SilentlyContinue'
    try {
        $rssUrl = "https://sourceforge.net/projects/equalizerapo/rss?path=/"
        $xml = [xml](Invoke-WebRequest -Uri $rssUrl -UseBasicParsing -ErrorAction Stop).Content
        $candidates = @()
        foreach ($item in $xml.rss.channel.Item) {
            $link = $item.link
            if ($link -match 'EqualizerAPO(?:64|-x64)-([\d.]+)\.exe/download$') {
                $verStr = $Matches[1]
                try {
                    $ver = [version]$verStr
                    $candidates += [PSCustomObject]@{ Version = $ver; Url = $link }
                } catch { }
            }
        }
        if ($candidates.Count -gt 0) {
            $best = $candidates | Sort-Object Version -Descending | Select-Object -First 1
            return $best.Url
        }
    } catch { }
    return $fallback
}

$script:VoicemeeterUrlResolver = {
    $fallback = "https://download.vb-audio.com/Download_CABLE/VoicemeeterSetup_v1122.zip"
    $ProgressPreference = 'SilentlyContinue'
    try {
        $page = (Invoke-WebRequest -Uri "https://vb-audio.com/Voicemeeter/index.htm" -UseBasicParsing -ErrorAction Stop).Content
        $m = [regex]::Match($page, 'download\.vb-audio\.com/Download_CABLE/VoicemeeterSetup[^"'']*\.zip', 'IgnoreCase')
        if ($m.Success) { return "https://$($m.Value)" }
    } catch { }
    return $fallback
}

$script:LeqUrlResolver = {
    $ProgressPreference = 'SilentlyContinue'
    try {
        $headers = @{ 'Accept' = 'application/vnd.github+json' }
        $release = Invoke-RestMethod 'https://api.github.com/repos/ArtIsWar/LEQControlPanel/releases/latest' -Headers $headers -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -eq 'LEQControlPanel.exe' } | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
    } catch { }
    return $null  # triggers FallbackUrl path
}

function Test-BinaryHeader {
    <#
    .SYNOPSIS
        Returns $true if the file starts with MZ (PE executable) or 7z (7-Zip SFX).
        Used to validate SourceForge downloads returned a real binary, not an HTML page.
    #>
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $header = New-Object byte[] 2
    $fs = [System.IO.File]::OpenRead($FilePath)
    try { $fs.Read($header, 0, 2) | Out-Null } finally { $fs.Close() }
    $str = [System.Text.Encoding]::ASCII.GetString($header)
    return ($str -eq 'MZ' -or $str -eq '7z')
}

function Start-ParallelDownloads {
    <#
    .SYNOPSIS
        Downloads multiple files concurrently using a runspace pool (for direct
        HTTP downloads) and main-thread BITS transfers (for SourceForge).
    .PARAMETER Specs
        Array of hashtables, each with:
          Key          - Identifier for the result (e.g. 'HiFiCable')
          DisplayName  - Friendly name for console output
          OutFile      - Destination file path
          Method       - 'IWR' (Invoke-WebRequest via runspace) or 'BITS' (BITS transfer)
          Url          - Download URL (for IWR) or $null if UrlResolver is set
          BaseUrl      - Base SourceForge URL before mirror suffix (for BITS)
          UrlResolver  - Scriptblock that returns a URL (runs in a runspace), or $null
    #>
    param(
        [hashtable[]]$Specs,
        [int]$TotalCount = 0,
        [string[]]$NonFatalKeys = @()
    )

    if ($Specs.Count -eq 0) { return @{} }

    # -- Runspace pool (for IWR downloads and URL resolution) ------------------
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 6)
    $pool.Open()

    $iwrScript = {
        param($url, $outFile, $prog, $key)
        $ProgressPreference    = 'SilentlyContinue'
        $ErrorActionPreference = 'Stop'
        # Best-effort HEAD purely so the progress row can show a percentage and an ETA.
        # Never fatal: without a total the row falls back to bytes-and-rate, which is
        # still far better than the bouncing bar this replaced. Measured 48-420ms
        # against every source we fetch over IWR.
        try {
            $h = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 8
            if ($h.Headers.ContainsKey('Content-Length')) {
                $len = [int64]($h.Headers['Content-Length'] | Select-Object -First 1)
                if ($len -gt 0) { $prog["$key.total"] = $len }
            }
        } catch { }
        # Hand the timeout clock back to the poller: the HEAD above must not be charged
        # against the spec's TimeoutSec, which is a budget for the transfer.
        $prog["$key.dlstart"] = [datetime]::UtcNow
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
    }

    # Tracking structures
    $urlJobs  = @{}   # Key -> @{ PS; Handle; Spec }
    $iwrJobs  = @{}   # Key -> @{ PS; Handle }
    $bitsJobs = @{}   # Key -> BITS job object
    $state    = @{}   # Key -> 'resolving' | 'downloading' | 'done' | 'error'
    $errors   = @{}   # Key -> error message
    $sizes    = @{}   # Key -> formatted final file size string (e.g. "[3.2 MB]")
    $started  = @{}   # Key -> [datetime] when download started (for timeout)
    $bitsMirrorIdx = @{}  # Key -> int (current mirror index for retry)
    $fbTried  = @{}   # Key -> $true once FallbackUrl has been started (one shot)
    $results  = @{}   # Key -> OutFile or $null

    # -- Live progress tracking ------------------------------------------------
    # $prog crosses the runspace boundary, so it is synchronized and uses FLAT composite
    # keys that are ALL pre-seeded below: a hashtable that never grows cannot rehash
    # under the reader, and StrictMode can never trip over a missing key. Only the
    # runspace writes it ("<key>.total" from the HEAD, "<key>.dlstart"); bytes-received
    # is read from the partial file on this thread instead.
    $prog      = [hashtable]::Synchronized(@{})
    $bytesPeak = @{}   # Key -> [int64]    high-water byte mark (stall detection)
    $moveAt    = @{}   # Key -> [datetime] when the byte count last increased
    $rate      = @{}   # Key -> [double]   smoothed bytes/sec
    $rateAt    = @{}   # Key -> [datetime] last rate sample
    $rateBytes = @{}   # Key -> [int64]    byte count at the last rate sample
    foreach ($sp in $Specs) {
        $prog["$($sp.Key).total"]   = [int64]0
        $prog["$($sp.Key).dlstart"] = [int64]0
        $bytesPeak[$sp.Key] = [int64]0
        $moveAt[$sp.Key]    = [datetime]::UtcNow
        $rate[$sp.Key]      = [double]0
        $rateAt[$sp.Key]    = [datetime]::UtcNow
        $rateBytes[$sp.Key] = [int64]0
    }

    # -- Helper: zero a key's progress counters --------------------------------
    # Every restart path (mirror rotation, FallbackUrl) reuses the SAME key, so without
    # this the bar would run backwards or sit on a stale byte count from the dead attempt.
    $resetProg = {
        param($key)
        $prog["$key.total"]   = [int64]0
        $prog["$key.dlstart"] = [int64]0
        $bytesPeak[$key] = [int64]0
        $moveAt[$key]    = [datetime]::UtcNow
        $rate[$key]      = [double]0
        $rateAt[$key]    = [datetime]::UtcNow
        $rateBytes[$key] = [int64]0
    }

    # -- Helper: start an IWR download in a runspace ---------------------------
    $startIwr = {
        param($key, $url, $outFile)
        & $resetProg $key
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript($iwrScript).AddArgument($url).AddArgument($outFile).AddArgument($prog).AddArgument($key)
        $iwrJobs[$key] = @{ PS = $ps; Handle = $ps.BeginInvoke() }
        $state[$key]   = 'downloading'
        $started[$key] = [datetime]::UtcNow
    }

    # -- Helper: start a BITS download -----------------------------------------
    $startBits = {
        param($key, $baseUrl, $outFile, $mirrorIdx)
        & $resetProg $key
        $mirror = $script:SourceForgeMirrors[$mirrorIdx]
        $url = $baseUrl + $mirror
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        $bitsJobs[$key] = Start-BitsTransfer -Source $url -Destination $outFile -Asynchronous -ErrorAction Stop
        $bitsMirrorIdx[$key] = $mirrorIdx
        $state[$key]   = 'downloading'
        $started[$key] = [datetime]::UtcNow
    }

    # -- Phase A: Fire URL-resolution runspaces --------------------------------
    foreach ($spec in $Specs) {
        if ($spec.UrlResolver) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            $null = $ps.AddScript($spec.UrlResolver)
            $urlJobs[$spec.Key] = @{ PS = $ps; Handle = $ps.BeginInvoke(); Spec = $spec }
            $state[$spec.Key] = 'resolving'
            $started[$spec.Key] = [datetime]::UtcNow
        }
    }

    # -- Phase B: Fire all downloads with known URLs ---------------------------
    foreach ($spec in $Specs) {
        if ($spec.UrlResolver) { continue }  # started above, will download after resolve
        if ($spec.Method -eq 'BITS') {
            try {
                & $startBits $spec.Key $spec.BaseUrl $spec.OutFile 0
            } catch {
                # BITS failed to start -- fall back to IWR
                $fbUrl = if ($spec.FallbackUrl) { $spec.FallbackUrl }
                         elseif ($spec.BaseUrl) { $spec.BaseUrl }
                         else { $spec.Url }
                try { & $startIwr $spec.Key $fbUrl $spec.OutFile }
                catch { $state[$spec.Key] = 'error'; $errors[$spec.Key] = "BITS and IWR both failed: $_" }
            }
        } else {
            & $startIwr $spec.Key $spec.Url $spec.OutFile
        }
    }

    # -- Phase C: Polling loop with live per-file progress --------------------
    $fi = 0
    $m = $script:BoxMargin
    $pad = $script:ScreenWidth
    $total = if ($TotalCount -gt 0) { $TotalCount } else { $Specs.Count }
    $skipped = $total - $Specs.Count
    $blockStart = [datetime]::UtcNow

    # $paint has to exist before the try so the finally can read it under StrictMode.
    $cp = Get-ConsolePaint
    $paint = @{
        On    = $cp.Enabled
        W     = $cp.Width
        LastW = $cp.Width
        Rows  = ($Specs.Count + 1)
        Cache = (New-Object -TypeName 'string[]' -ArgumentList ($Specs.Count + 1))
    }

    # A row is 2 + glyph + 18-char name + 26-char bar + 2 + up to 40 of detail. On a
    # window too narrow for that, give up indent rather than let a row wrap -- wrapping
    # turns one row into two and destroys the block arithmetic Write-BlockLines relies on.
    $rowNeed = 90
    $ind = $script:BoxMargin
    if (($cp.Width - $ind.Length) -lt $rowNeed) {
        $room = $cp.Width - $rowNeed
        if ($room -lt 0) { $room = 0 }
        $ind = ' ' * $room
    }

    # -- The live block --------------------------------------------------------
    # One header row plus one row per spec, FIXED for the whole run: finished items
    # become a static row in place, so the block never changes height and the cursor
    # arithmetic stays valid. Invoked with &, so only hashtable mutations propagate --
    # $paint.On = $false works, a plain scalar assignment would not.
    $render = {
        param([bool]$Final)

        $lines  = New-Object -TypeName 'string[]' -ArgumentList $paint.Rows
        $colors = New-Object -TypeName 'string[]' -ArgumentList $paint.Rows
        $nowU   = [datetime]::UtcNow

        $doneCount = @($state.Values | Where-Object { $_ -eq 'done' -or $_ -eq 'error' }).Count + $skipped
        $hdrPct = 0
        if ($total -gt 0) { $hdrPct = [int](100 * $doneCount / $total) }
        $lines[0] = "$ind  Downloading $doneCount/$total " + (Get-ProgressBar -Width 24 -Percent $hdrPct) +
                    "  " + (Format-Duration ($nowU - $blockStart).TotalSeconds)
        $colors[0] = if ($Final) { 'Green' } else { 'DarkGray' }

        $ri = 1
        foreach ($sp in $Specs) {
            $k = $sp.Key
            $st = 'queued'
            if ($state.ContainsKey($k)) { $st = $state[$k] }

            # -- Bytes so far, and a total if one is known --------------------
            $got = [int64]0
            $tot = [int64]0
            if ($bitsJobs.ContainsKey($k)) {
                # Live COM-backed properties; no Get-BitsTransfer refetch needed. Both are
                # UInt64, so cast before any arithmetic or a subtraction underflows to ~1.8e19.
                # BytesTotal reads BG_SIZE_UNKNOWN (UInt64::MaxValue) until BITS has the
                # response headers -- using that as a denominator pins the bar at 0% forever.
                try {
                    $bjr = $bitsJobs[$k]
                    $got = [int64]$bjr.BytesTransferred
                    $bt  = $bjr.BytesTotal
                    if ($bt -gt 0 -and $bt -ne [uint64]::MaxValue) { $tot = [int64]$bt }
                } catch { }
            } elseif ($st -eq 'downloading') {
                # IWR streams to disk, so the partial file's length IS the byte count.
                # BITS is excluded above because it writes to a .BITxxxx.tmp sidecar and
                # only renames on Complete-BitsTransfer.
                $partial = Get-Item $sp.OutFile -ErrorAction SilentlyContinue
                if ($partial) { $got = [int64]$partial.Length }
                $pt = $prog["$k.total"]
                if ($pt -gt 0) { $tot = [int64]$pt }
            }

            if ($got -gt $bytesPeak[$k]) {
                $bytesPeak[$k] = $got
                $moveAt[$k]    = $nowU
            }
            # Sample the rate about once a second and smooth it, so the readout does not
            # jitter between frames.
            $dt = ($nowU - $rateAt[$k]).TotalSeconds
            if ($dt -ge 1.0) {
                $inst = ($got - $rateBytes[$k]) / $dt
                if ($inst -lt 0) { $inst = 0 }
                if ($rate[$k] -le 0) { $rate[$k] = $inst }
                else { $rate[$k] = (0.6 * $rate[$k]) + (0.4 * $inst) }
                $rateAt[$k]    = $nowU
                $rateBytes[$k] = $got
            }

            # -- Row ------------------------------------------------------------
            $glyph  = ' '
            $color  = 'DarkGray'
            $bar    = ' ' * 26
            $detail = ''
            if ($st -eq 'done') {
                $glyph  = [char]0x2713
                $color  = 'Green'
                $bar    = Get-ProgressBar -Width 24 -Percent 100
                # $sizes carries the tally's bracketed form; the row already has a
                # bracketed bar beside it, so drop them here.
                if ($sizes.ContainsKey($k)) { $detail = "$($sizes[$k])".Trim('[', ']') }
            } elseif ($st -eq 'error') {
                # No bar on a failed row -- the message takes that column, so it reads
                # like the plain tally instead of trailing 26 blank spaces.
                $glyph = '!'
                $bar   = ''
                if ($NonFatalKeys -contains $k) {
                    $color  = 'Yellow'
                    $detail = 'FAILED (non-fatal, will prompt later)'
                } else {
                    $color  = 'Red'
                    $detail = 'FAILED'
                }
            } elseif ($st -eq 'resolving') {
                $bar    = Get-ProgressBar -Width 24 -Percent -1 -Frame ($fi * 2)
                $detail = 'finding latest version...'
                $el = ($nowU - $started[$k]).TotalSeconds
                if ($el -ge 5) { $detail += "  {0:N0}s" -f $el }
            } elseif ($got -le 0) {
                $bar    = Get-ProgressBar -Width 24 -Percent -1 -Frame ($fi * 2)
                $detail = 'connecting...'
            } elseif ($tot -gt 0) {
                # Hold at 99 until the state actually flips, so a row never reads 100%
                # while it is still spinning.
                $pct = [int](100 * $got / $tot)
                if ($pct -gt 99) { $pct = 99 }
                if ($pct -lt 0) { $pct = 0 }
                $bar    = Get-ProgressBar -Width 24 -Percent $pct
                # Pad the whole "x/y MB" run rather than its parts, so a 3-digit total
                # does not open a gap before the unit.
                $detail = "{0,-15} {1,3}%" -f ("{0:N1}/{1:N1} MB" -f ($got / 1MB), ($tot / 1MB)), $pct
                if ($rate[$k] -gt 0) {
                    $detail += "  {0,5:N1} MB/s" -f ($rate[$k] / 1MB)
                    $detail += "  " + (Format-Duration (($tot - $got) / $rate[$k]))
                }
            } else {
                # No Content-Length (HEAD failed, or a chunked response). Bytes and rate
                # still prove it is moving, which is the whole point. Same column widths
                # as above so rows stay aligned with their neighbours.
                $bar    = Get-ProgressBar -Width 24 -Percent -1 -Frame ($fi * 2)
                $detail = "{0,-15}    " -f ("{0:N1} MB" -f ($got / 1MB))
                if ($rate[$k] -gt 0) { $detail += "  {0,5:N1} MB/s" -f ($rate[$k] / 1MB) }
            }

            $lines[$ri]  = "$ind  $glyph $($sp.DisplayName.PadRight(18))$bar  $detail"
            $colors[$ri] = $color
            $ri++
        }

        # A resize reflows rows that are already on screen, so the saved geometry is
        # stale: re-reserve a fresh block instead of painting into the wrong rows.
        $wNow = $paint.W
        try { $wNow = $Host.UI.RawUI.BufferSize.Width - 1 } catch { }
        if ($wNow -ne $paint.LastW -and $wNow -gt 0) {
            $paint.W = $wNow
            $paint.LastW = $wNow
            for ($i = 0; $i -lt $paint.Rows; $i++) { $paint.Cache[$i] = $null }
            for ($i = 0; $i -lt $paint.Rows; $i++) { Write-Host "" }
        }
        if (-not (Write-BlockLines -Lines $lines -Colors $colors -Width $paint.W -Cache $paint.Cache)) {
            $paint.On = $false
        }
    }

    if ($paint.On) {
        # Reserve the rows the block will own. Every frame re-derives its top row
        # RELATIVE to the cursor, so scrolling can never invalidate this.
        for ($i = 0; $i -lt $paint.Rows; $i++) { Write-Host "" }
    } else {
        # Print what we're about to download
        $nameList = ($Specs | ForEach-Object { $_.DisplayName }) -join ', '
        Write-Host "$m  Downloading: $nameList" -ForegroundColor DarkGray
    }

    try {

    # NOTHING inside this loop may write to the console except $render. Any stray output
    # scrolls the reserved rows out from under the cursor arithmetic, and the next frame
    # then repaints over live text. Keep new diagnostics out of here.
    while (@($state.Values | Where-Object { $_ -ne 'done' -and $_ -ne 'error' }).Count -gt 0) {

        # -- Check URL-resolution completions ----------------------------------
        foreach ($key in @($urlJobs.Keys)) {
            $uj = $urlJobs[$key]
            if ($uj.Handle.IsCompleted) {
                $resolvedUrl = $null
                try {
                    $out = $uj.PS.EndInvoke($uj.Handle)
                    if ($out -and $out.Count -gt 0) { $resolvedUrl = $out[$out.Count - 1] }
                } catch { }
                $uj.PS.Dispose()
                $spec = $uj.Spec
                $urlJobs.Remove($key)

                if (-not $resolvedUrl) {
                    if ($spec.FallbackUrl) {
                        # Resolver returned nothing -- use FallbackUrl via IWR
                        try { & $startIwr $key $spec.FallbackUrl $spec.OutFile }
                        catch { $state[$key] = 'error'; $errors[$key] = "URL resolution and fallback both failed: $_" }
                    } else {
                        $state[$key] = 'error'
                        $errors[$key] = 'URL resolution failed'
                    }
                    continue
                }

                # Start the actual download
                if ($spec.Method -eq 'BITS') {
                    $spec.BaseUrl = $resolvedUrl
                    try {
                        & $startBits $key $resolvedUrl $spec.OutFile 0
                    } catch {
                        # BITS failed to start -- fall back to IWR
                        $fbUrl = if ($spec.FallbackUrl) { $spec.FallbackUrl }
                                 elseif ($resolvedUrl)  { $resolvedUrl }
                                 else { $spec.Url }
                        try { & $startIwr $key $fbUrl $spec.OutFile }
                        catch { $state[$key] = 'error'; $errors[$key] = "BITS and IWR both failed: $_" }
                    }
                } else {
                    $spec.Url = $resolvedUrl
                    & $startIwr $key $resolvedUrl $spec.OutFile
                }
            }
        }

        # -- Check IWR completions ---------------------------------------------
        foreach ($key in @($iwrJobs.Keys)) {
            $ij = $iwrJobs[$key]
            if ($ij.Handle.IsCompleted) {
                $spec = $Specs | Where-Object { $_.Key -eq $key }
                $iwrErr = $null
                try {
                    $ij.PS.EndInvoke($ij.Handle)
                    if (-not ((Test-Path $spec.OutFile) -and (Get-Item $spec.OutFile).Length -gt 0)) {
                        throw "File missing or empty after download"
                    }
                    # SourceForge serves an HTML interstitial instead of the file often
                    # enough that the BITS lane has always screened for it. The check
                    # belongs to the URL, not the transport, so it travels with any spec
                    # that SourceForge can answer -- which now includes IWR fallbacks.
                    if ($spec.RequireBinary -and -not (Test-BinaryHeader $spec.OutFile)) {
                        throw "Server returned a non-binary body (probably an HTML page)"
                    }
                    $fileLen = (Get-Item $spec.OutFile).Length
                    $sizes[$key] = Format-ByteSize -Bytes $fileLen -Bracket
                    $state[$key] = 'done'
                } catch {
                    $iwrErr = "$_"
                }
                $ij.PS.Dispose()
                $iwrJobs.Remove($key)

                # A failed IWR download used to be terminal: FallbackUrl was reachable
                # only from the resolver and BITS lanes. That was survivable while the
                # primary was SourceForge-over-BITS, but with the CDN as primary it would
                # make a CDN outage fatal for a load-bearing component. One shot only,
                # guarded by $fbTried, so a fallback that fails the same way cannot loop.
                if ($iwrErr) {
                    if ($spec.FallbackUrl -and -not $fbTried.ContainsKey($key)) {
                        $fbTried[$key] = $true
                        Remove-Item $spec.OutFile -Force -ErrorAction SilentlyContinue
                        try { & $startIwr $key $spec.FallbackUrl $spec.OutFile }
                        catch {
                            $state[$key]  = 'error'
                            $errors[$key] = "$iwrErr; fallback failed: $_"
                        }
                    } else {
                        $state[$key]  = 'error'
                        $errors[$key] = $iwrErr
                    }
                }
            }
        }

        # -- Check BITS completions (with mirror fallback) ---------------------
        foreach ($key in @($bitsJobs.Keys)) {
            $bj = $bitsJobs[$key]
            $spec = $Specs | Where-Object { $_.Key -eq $key }

            if ($bj.JobState -eq 'Transferred') {
                Complete-BitsTransfer $bj
                if (Test-BinaryHeader $spec.OutFile) {
                    $fileLen = (Get-Item $spec.OutFile -ErrorAction SilentlyContinue).Length
                    $sizes[$key] = Format-ByteSize -Bytes $fileLen -Bracket
                    $state[$key] = 'done'
                } else {
                    # Got HTML instead of binary -- try next mirror
                    Remove-Item $spec.OutFile -Force -ErrorAction SilentlyContinue
                    $nextIdx = $bitsMirrorIdx[$key] + 1
                    if ($nextIdx -lt $script:SourceForgeMirrors.Count) {
                        try {
                            & $startBits $key $spec.BaseUrl $spec.OutFile $nextIdx
                        } catch {
                            $state[$key] = 'error'
                            $errors[$key] = "BITS mirror retry failed: $_"
                        }
                    } elseif ($spec.FallbackUrl) {
                        # All mirrors returned HTML -- try CDN fallback via IWR
                        try { & $startIwr $key $spec.FallbackUrl $spec.OutFile }
                        catch { $state[$key] = 'error'; $errors[$key] = "All mirrors and CDN fallback failed: $_" }
                    } else {
                        $state[$key] = 'error'
                        $errors[$key] = "All SourceForge mirrors returned non-binary content"
                    }
                }
                $bitsJobs.Remove($key)
            } elseif ($bj.JobState -eq 'Error' -or $bj.JobState -eq 'TransientError') {
                Remove-BitsTransfer $bj -ErrorAction SilentlyContinue
                $bitsJobs.Remove($key)
                $nextIdx = $bitsMirrorIdx[$key] + 1
                if ($nextIdx -lt $script:SourceForgeMirrors.Count) {
                    try {
                        & $startBits $key $spec.BaseUrl $spec.OutFile $nextIdx
                    } catch {
                        $state[$key] = 'error'
                        $errors[$key] = "BITS mirror retry failed: $_"
                    }
                } elseif ($spec.FallbackUrl) {
                    # All mirrors failed -- try CDN fallback via IWR
                    try { & $startIwr $key $spec.FallbackUrl $spec.OutFile }
                    catch { $state[$key] = 'error'; $errors[$key] = "All mirrors and CDN fallback failed: $_" }
                } else {
                    $state[$key] = 'error'
                    $errors[$key] = "All SourceForge mirrors failed"
                }
            }
        }

        # -- Timeout check -----------------------------------------------------
        foreach ($key in @($started.Keys)) {
            $elapsed = ([datetime]::UtcNow - $started[$key]).TotalSeconds
            if ($state[$key] -eq 'resolving' -and $elapsed -gt 120) {
                # Cancel timed-out URL resolver
                if ($urlJobs.ContainsKey($key)) {
                    try { $urlJobs[$key].PS.Stop() } catch { }
                    try { $urlJobs[$key].PS.Dispose() } catch { }
                    $urlJobs.Remove($key)
                }
                $toSpec = $Specs | Where-Object { $_.Key -eq $key }
                if ($toSpec.FallbackUrl) {
                    # Resolver timed out -- use FallbackUrl via IWR
                    try { & $startIwr $key $toSpec.FallbackUrl $toSpec.OutFile }
                    catch { $state[$key] = 'error'; $errors[$key] = "URL resolution timed out and fallback failed: $_" }
                } else {
                    $state[$key] = 'error'
                    $errors[$key] = 'URL resolution timed out (120s)'
                }
            }
            elseif ($state[$key] -eq 'downloading') {
                # The IWR runspace stamps this once its HEAD is done, so the Content-Length
                # probe is not charged against a budget meant for the transfer. Idempotent.
                $ds = $prog["$key.dlstart"]
                if ($ds -is [datetime] -and $ds -gt $started[$key]) {
                    $started[$key] = $ds
                    $elapsed = ([datetime]::UtcNow - $ds).TotalSeconds
                }

                $dlSpec = $Specs | Where-Object { $_.Key -eq $key }
                $dlTimeout = if ($dlSpec.TimeoutSec) { $dlSpec.TimeoutSec } else { 120 }

                # Now that bytes are tracked, a dead socket can fail in 90s instead of
                # burning the whole wall budget (600s for LEQ). Only ever applied while
                # the transport says it should be moving: BITS backs off and retries on
                # its own from Queued/Connecting, and killing it there would turn a
                # recoverable condition into a hard failure.
                $stalled = $false
                if ($bitsJobs.ContainsKey($key)) {
                    $js = ''
                    try { $js = "$($bitsJobs[$key].JobState)" } catch { }
                    if ($js -ne 'Transferring') { $moveAt[$key] = [datetime]::UtcNow }
                    else { $stalled = (([datetime]::UtcNow - $moveAt[$key]).TotalSeconds -gt 90) }
                } else {
                    $stalled = ($bytesPeak[$key] -gt 0 -and
                                ([datetime]::UtcNow - $moveAt[$key]).TotalSeconds -gt 90)
                }

                if ($elapsed -gt $dlTimeout -or $stalled) {
                    # Cancel timed-out download
                    if ($iwrJobs.ContainsKey($key)) {
                        $iwrJobs[$key].PS.Stop()
                        $iwrJobs[$key].PS.Dispose()
                        $iwrJobs.Remove($key)
                    }
                    if ($bitsJobs.ContainsKey($key)) {
                        Remove-BitsTransfer $bitsJobs[$key] -ErrorAction SilentlyContinue
                        $bitsJobs.Remove($key)
                    }
                    $state[$key] = 'error'
                    $errors[$key] = if ($stalled) { "Download stalled (no data for 90s)" }
                                    else { "Download timed out ($($dlTimeout)s)" }
                }
            }
        }

        # -- Render progress ---------------------------------------------------
        if ($paint.On) {
            & $render $false
        } else {
            $doneCount = @($state.Values | Where-Object { $_ -eq 'done' -or $_ -eq 'error' }).Count + $skipped
            $bar = Get-ProgressBar -Width 30 -Percent -1 -Frame $fi
            $line = "$m  Downloading $doneCount/$total $bar"
            Write-Host "`r$($line.PadRight($pad))" -NoNewline -ForegroundColor DarkGray
        }

        Start-Sleep -Milliseconds 250
        $fi++
    }

    # -- Print final results per item -----------------------------------------
    if ($paint.On) {
        # The block already shows every row's outcome; one last paint settles it and
        # it stays in the scrollback exactly as it stands.
        & $render $true
        Write-Host ""
    } else {
        $doneBar = Get-ProgressBar -Width 30 -Percent 100
        Write-Host "`r$("$m  Downloading $total/$total $doneBar".PadRight($pad))" -ForegroundColor Green
        foreach ($spec in $Specs) {
            $s = $state[$spec.Key]
            $name = $spec.DisplayName
            if ($s -eq 'done') {
                $icon = [char]0x2713
                $szLabel = if ($sizes.ContainsKey($spec.Key)) { " $($sizes[$spec.Key])" } else { "" }
                Write-Host "$m  $icon $name$szLabel" -ForegroundColor Green
            } elseif ($NonFatalKeys -contains $spec.Key) {
                Write-Host "$m  ! $name FAILED (non-fatal, will prompt later)" -ForegroundColor Yellow
            } else {
                Write-Host "$m  ! $name FAILED" -ForegroundColor Red
            }
        }
    }

    } finally {
        # -- Cleanup (always runs, even on exception) --------------------------
        # Every frame ends with the cursor restored below the block, so this only has to
        # catch a throw mid-paint -- but leaving the cursor stranded inside the block
        # would have the retry menu draw over live rows.
        if ($paint.On) {
            try {
                if ($Host.UI.RawUI.CursorPosition.X -ne 0) { Write-Host "" }
            } catch { }
        }
        foreach ($key in @($iwrJobs.Keys)) {
            try { $iwrJobs[$key].PS.Stop() } catch { }
            try { $iwrJobs[$key].PS.Dispose() } catch { }
        }
        foreach ($key in @($bitsJobs.Keys)) {
            Remove-BitsTransfer $bitsJobs[$key] -ErrorAction SilentlyContinue
        }
        $pool.Close()
        $pool.Dispose()
    }

    # -- Error check -----------------------------------------------------------
    # Separate non-fatal errors (e.g. SoundControl) from fatal ones
    $script:DownloadWarnings = @{}
    if ($errors.Count -gt 0) {
        $fatalErrors = @{}
        foreach ($entry in @($errors.GetEnumerator())) {
            if ($NonFatalKeys -contains $entry.Key) {
                $script:DownloadWarnings[$entry.Key] = $entry.Value
            } else {
                $fatalErrors[$entry.Key] = $entry.Value
            }
        }
        if ($fatalErrors.Count -gt 0) {
            $msg = ($fatalErrors.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "; "
            throw "Failed to download: $msg"
        }
    }

    # -- Build result hashtable ------------------------------------------------
    $results = @{}
    foreach ($spec in $Specs) {
        if ($script:DownloadWarnings.ContainsKey($spec.Key)) {
            $results[$spec.Key] = $null
        } else {
            $results[$spec.Key] = $spec.OutFile
        }
    }
    return $results
}

function Get-Downloads {
    <#
    .SYNOPSIS
        Downloads components for installation. Skips already-installed components.
        Downloads run in parallel for speed.
    .PARAMETER IncludeVirtualAudio
        If set, includes VB-CABLE and Voicemeeter (PATH B: DAC/amp/onboard).
        If not set, downloads shared components only (PATH A: approved device).
    .PARAMETER WantVoicemeeter
        Whether Voicemeeter is wanted at all. Defaults to true for backwards
        compatibility. Independent of IncludeVirtualAudio so a user who already
        runs Wave Link or Voicemeeter Banana/Potato can take the rest of the
        stack without a mixer being installed underneath them.
    #>
    param(
        [switch]$IncludeVirtualAudio,
        [bool]$WantVoicemeeter = $true
    )

    if (-not (Test-Path $script:TempPath)) {
        New-Item -ItemType Directory -Path $script:TempPath -Force | Out-Null
    }

    # SoundControlPresent is NOT a download path -- it records "already installed,
    # nothing to fetch", which $files.SoundControl (a temp file path) cannot express:
    # a null there means the download FAILED, and the caller reacts accordingly.
    $files = @{
        VBCable             = $null
        Voicemeeter         = $null
        ReaPlugs            = $null
        EAPO                = $null
        HeSuVi              = $null
        SoundControl        = $null
        SoundControlPresent = $false
    }

    # -- Detect what is already installed ------------------------------------
    $reaplugsDlls = @(Get-ChildItem "${env:ProgramFiles}\VSTPlugins\ReaPlugs\*.dll" -ErrorAction SilentlyContinue)
    $skipReaPlugs = ($reaplugsDlls -and $reaplugsDlls.Count -ge 5)
    # E-APO has NO skip. It is fetched and re-run even when already installed, because
    # its setup is the only thing that reopens Device Selector -- and [1] Install has
    # just removed the retired Hi-Fi Cable an existing E-APO was very likely still bound
    # to, then laid down VB-CABLE in its place. Re-running it is also what creates the
    # ArtTuneDB folder icon, its .url files and the desktop shortcut, none of which an
    # existing-E-APO user used to get. E-APO's installer handles installing over itself.
    # $eapoPresent only words the message below.
    $eapoPresent = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO\config")
    $skipHeSuVi = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO\config\HeSuVi")
    # LEQ is a ~200 MB fetch, so a re-run must not repeat it. The presence check
    # targets the exact path Install-SoundControl copies to, which is also what the
    # completion menu launches and what Uninstall-SoundControl removes.
    $leqExe = Join-Path $env:LOCALAPPDATA "Programs\LEQControlPanel\LEQControlPanel.exe"
    $skipSoundControl = Test-Path -LiteralPath $leqExe

    # BITS is started further down, and only if a spec actually asks for it. It used to
    # be started here whenever E-APO or HeSuVi was wanted, which is now exactly the wrong
    # gate: both fetch from the CDN over IWR, so starting BITS would buy nothing and cost
    # a measured 4.2s service cold start on a PC where BITS is stopped.

    if ($IncludeVirtualAudio) {
        # VB-CABLE presence is a POSITIVE check: the endpoints must actually
        # resolve. Get-ArtTuneEndpoints matches the interface description
        # 'VB-Audio Virtual Cable' exactly, so the retired Hi-Fi Cable (which
        # enumerates as "VB-Audio Hi-Fi Cable") cannot masquerade as an installed
        # cable and silently suppress the install.
        #
        # HEALTHY means all three: 8ch render + 16ch render + capture. A clean
        # VB-CABLE v45 ships all three Active, and the 16ch render is what the
        # spatial profiles need -- so "some endpoint exists" is not good enough.
        $eps = Get-ArtTuneEndpoints
        $vbAny     = [bool]($eps.Render8 -or $eps.Render16 -or $eps.Capture)
        $vbHealthy = [bool]($eps.Render8 -and $eps.Render16 -and $eps.Capture)
        $vbPartial = ($vbAny -and -not $vbHealthy)

        # Skip the download whenever ANY endpoint exists, healthy or not: VB-CABLE
        # setup refuses to install over an existing copy (non-zero exit, see
        # Install-VBCable), so re-running it cannot repair a partial install. The
        # real fix is Start Clean -- remove, reboot, reinstall -- so say that
        # instead of silently proceeding with a broken cable.
        $skipVBCable = $vbAny

        # Whether Voicemeeter is WANTED is entirely the caller's decision: the
        # install path asks about every mixer it found, paid-edition override
        # included, and hands the verdict down in $WantVoicemeeter. Re-deciding any
        # of that here would silently veto a confirmation the user just gave.
        #
        # The only thing this layer adds is "we already have it", and that is gated
        # on the Standard EXE -- NOT on .Present, which is also true for a leftover
        # uninstall registry key with nothing on disk. Skipping on .Present would
        # hand that user a finished install with no mixer in it at all.
        $vmEdition = Test-VoicemeeterEdition
        $skipVoicemeeter = ((-not $WantVoicemeeter) -or $vmEdition.Standard)
    }

    # -- Print skip messages for already-installed components ----------------
    if ($IncludeVirtualAudio) {
        if ($vbHealthy) {
            Write-Host "$($script:BoxMargin)VB-CABLE already installed, skipping download." -ForegroundColor DarkGray
        } elseif ($vbPartial) {
            $missing = @()
            if (-not $eps.Render8)  { $missing += "8ch render (Art Tune)" }
            if (-not $eps.Render16) { $missing += "16ch render (Art Tune +)" }
            if (-not $eps.Capture)  { $missing += "capture (Art Tune Unified Output)" }
            Write-Host ""
            Write-Host "$($script:BoxMargin)WARNING: VB-CABLE is installed but incomplete." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Missing: $($missing -join ', ')" -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Setup cannot repair this in place -- VB-CABLE refuses to install" -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)over an existing copy. Use [2] Start Clean to remove it, restart," -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)then run [1] Install for a complete cable." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Continuing with the endpoints that do exist." -ForegroundColor DarkGray
            Write-Host ""
        }
        # Keyed on the same flags the skip decision uses. The old .Present test
        # announced a skip and then queued the download anyway.
        if ($vmEdition.Standard) {
            Write-Host "$($script:BoxMargin)$($vmEdition.Name) already installed, skipping download." -ForegroundColor DarkGray
        } elseif (-not $WantVoicemeeter) {
            Write-Host "$($script:BoxMargin)Skipping Voicemeeter (not requested)." -ForegroundColor DarkGray
        }
    }
    if ($skipReaPlugs) { Write-Host "$($script:BoxMargin)ReaPlugs already installed, skipping download." -ForegroundColor DarkGray }
    if ($eapoPresent)  { Write-Host "$($script:BoxMargin)Equalizer APO already installed -- reinstalling it to rebind your devices." -ForegroundColor DarkGray }
    if ($skipHeSuVi)   { Write-Host "$($script:BoxMargin)HeSuVi already installed, skipping download." -ForegroundColor DarkGray }
    if ($skipSoundControl) { Write-Host "$($script:BoxMargin)LEQ Control Panel already installed, skipping download." -ForegroundColor DarkGray }

    # -- Build download specs ------------------------------------------------
    $totalComponents = if ($IncludeVirtualAudio) { 6 } else { 4 }
    $specs = @()

    if ($IncludeVirtualAudio) {
        if (-not $skipVBCable) {
            $files.VBCable = Join-Path $script:TempPath "VBCableSetup.zip"
            $specs += @{
                Key           = 'VBCable'
                DisplayName   = 'VB-CABLE'
                OutFile       = $files.VBCable
                Method        = 'IWR'
                Url           = 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip'
                BaseUrl       = $null
                UrlResolver   = $null
                FallbackUrl   = $null
                RequireBinary = $false   # a .zip opens 'PK'; Test-BinaryHeader wants MZ or 7z
                TimeoutSec    = 120
            }
        }

        if (-not $skipVoicemeeter) {
            $files.Voicemeeter = Join-Path $script:TempPath "VoicemeeterSetup.zip"
            $specs += @{
                Key           = 'Voicemeeter'
                DisplayName   = 'Voicemeeter'
                OutFile       = $files.Voicemeeter
                Method        = 'IWR'
                Url           = $null
                BaseUrl       = $null
                UrlResolver   = $script:VoicemeeterUrlResolver
                FallbackUrl   = $null
                RequireBinary = $false   # .zip, as above
                TimeoutSec    = 135
            }
        }
    }

    if (-not $skipReaPlugs) {
        $files.ReaPlugs = Join-Path $script:TempPath "reaplugs_x64.exe"
        $specs += @{
            Key           = 'ReaPlugs'
            DisplayName   = 'ReaPlugs'
            OutFile       = $files.ReaPlugs
            Method        = 'IWR'
            Url           = 'https://www.reaper.fm/reaplugs/reaplugs236_x64-install.exe'
            BaseUrl       = $null
            UrlResolver   = $null
            FallbackUrl   = $null
            RequireBinary = $false   # reaper.fm serves the exe directly, no interstitial
            TimeoutSec    = 120
        }
    }

    # Unconditional -- see the $eapoPresent note above for why there is no skip.
    #
    # CDN primary, SourceForge fallback. Both are GPL projects we are entitled to
    # rehost, and the mirror measured 20x faster to first byte (0.25s vs 5.5s) --
    # SourceForge costs a BITS service cold start plus a redirect-to-mirror handoff,
    # and every failed mirror got a fresh 120s budget before the CDN was even tried.
    #
    # PINNED, deliberately. This used to resolve the newest release from the
    # SourceForge RSS feed; it now takes the same 1.4.2 that ArtTuneKit's installer
    # bundles as a component, so every user gets the build the library configs were
    # validated against. A new E-APO release needs a manual CDN re-upload -- see
    # $script:EapoUrlResolver for how to hand version selection back to SourceForge.
    $files.EAPO = Join-Path $script:TempPath "EqualizerAPO64.exe"
    $specs += @{
        Key           = 'EAPO'
        DisplayName   = 'Equalizer APO'
        OutFile       = $files.EAPO
        Method        = 'IWR'
        Url           = 'https://cdn.artiswar.io/other-installers/EqualizerAPO-x64-1.4.2.exe'
        BaseUrl       = $null
        UrlResolver   = $null
        FallbackUrl   = 'https://sourceforge.net/projects/equalizerapo/files/1.4/EqualizerAPO64-1.4.exe/download'
        RequireBinary = $true
        TimeoutSec    = 120
    }

    if (-not $skipHeSuVi) {
        # CDN primary, SourceForge fallback. The CDN copy is byte-identical: 27,270,486
        # bytes, the same length SourceForge reports for HeSuVi_2.0.0.1.exe.
        $files.HeSuVi = Join-Path $script:TempPath "HeSuVi.exe"
        $specs += @{
            Key           = 'HeSuVi'
            DisplayName   = 'HeSuVi'
            OutFile       = $files.HeSuVi
            Method        = 'IWR'
            Url           = 'https://cdn.artiswar.io/other-installers/HeSuVi_2.0.0.1.exe'
            BaseUrl       = $null
            UrlResolver   = $null
            FallbackUrl   = 'https://sourceforge.net/projects/hesuvi/files/HeSuVi_2.0.0.1.exe/download'
            RequireBinary = $true
            TimeoutSec    = 120
        }
    }

    # LEQ Control Panel
    if ($skipSoundControl) {
        $files.SoundControlPresent = $true
    } else {
        $files.SoundControl = Join-Path $script:TempPath "LEQControlPanel.exe"
        $specs += @{
            Key           = 'SoundControl'
            DisplayName   = 'LEQ Control Panel'
            OutFile       = $files.SoundControl
            Method        = 'IWR'
            Url           = $null
            BaseUrl       = $null
            UrlResolver   = $script:LeqUrlResolver
            FallbackUrl   = 'https://cdn.artiswar.io/LEQControlPanel.exe'
            RequireBinary = $false   # GitHub asset then CDN; neither serves an interstitial
            TimeoutSec    = 600
        }
    }

    # -- Ensure BITS is available, but ONLY if something actually uses it -----
    # Gated on the built spec list rather than on which components were requested, so
    # the service is never started for a run that will not touch it. No spec ships with
    # Method = 'BITS' today; the transport and its SourceForge mirror rotation are kept
    # for any future source that needs them, and this gate turns itself back on.
    if (@($specs | Where-Object { $_.Method -eq 'BITS' }).Count -gt 0) {
        try {
            Ensure-BitsRunning
        } catch {
            throw "BITS service could not be started. If this is a managed PC, ask your IT admin to enable BITS."
        }
    }

    # -- Download everything in parallel -------------------------------------
    try {
        if ($specs.Count -gt 0) {
            $dlResults = Start-ParallelDownloads -Specs $specs -TotalCount $totalComponents -NonFatalKeys @('SoundControl')
        }

        # Clear SoundControl path if its download failed (non-fatal)
        if ($script:DownloadWarnings -and $script:DownloadWarnings.ContainsKey('SoundControl')) {
            $files.SoundControl = $null
        }

        return $files
    } finally {
        Restore-BitsState
    }
}

function Get-UrlToFile {
    <#
    .SYNOPSIS
        Downloads a single file with a live byte counter and a hard timeout.
        Returns $true on success, $false on any failure (never throws).
    .DESCRIPTION
        Same Start-Job + Write-Wait shape as Get-HrirFile: the transfer runs in a job so
        this thread stays free to animate, and the partial file's length is the progress
        readout. For one-off fetches that do not warrant the parallel downloader.
    #>
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Label,
        [int]$TimeoutSeconds = 300
    )

    Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
    $job = Start-Job -ScriptBlock {
        param($u, $o)
        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing -ErrorAction Stop
    } -ArgumentList $Url, $OutFile

    $outRef = $OutFile
    $finished = Write-Wait -Message $Label -Until { $job.State -ne 'Running' } -TimeoutSeconds $TimeoutSeconds -Progress {
        $pf = Get-Item $outRef -ErrorAction SilentlyContinue
        if ($pf) { Format-ByteSize -Bytes $pf.Length -Bracket }
    }

    $failed = ($job.State -eq 'Failed')
    $err = ''
    if ($failed) {
        # The terminating exception, not Receive-Job: -ErrorAction SilentlyContinue drops
        # the error records before 2>&1 can capture them, which leaves the message blank.
        try {
            $reason = $job.ChildJobs[0].JobStateInfo.Reason
            if ($reason) { $err = $reason.Message }
        } catch { }
        if (-not $err) { try { $err = "$(Receive-Job $job 2>&1 | Select-Object -First 1)" } catch { $err = "$_" } }
    }
    if (-not $finished) { try { Stop-Job $job -ErrorAction SilentlyContinue } catch { } }
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    $done = Get-Item $OutFile -ErrorAction SilentlyContinue
    if (-not $finished -or $failed -or -not $done -or $done.Length -le 0) {
        # Never leave a truncated file behind: the next attempt writes to the same path
        # and a half-downloaded zip that survives is worse than no zip at all.
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        if (-not $finished) {
            Write-Host "$($script:BoxMargin)Download timed out ($($TimeoutSeconds)s)." -ForegroundColor Yellow
        } elseif ($failed) {
            Write-Host "$($script:BoxMargin)Download failed: $err" -ForegroundColor Yellow
        } else {
            Write-Host "$($script:BoxMargin)Download produced no data." -ForegroundColor Yellow
        }
        return $false
    }
    return $true
}

# ============================================================================
# SECTION 4: Uninstall Functions
# ============================================================================


function Backup-ArtTuneLibrary {
    <#
    .SYNOPSIS
        Backs up the ArtTuneDB library folder before destructive operations.
    .OUTPUTS
        Backup folder path if successful, $null otherwise.
    .PARAMETER Rolling
        Use a single fixed backup dest (library-previous), overwriting any prior
        backup, instead of a timestamped folder. Used by the library updater.
    #>
    param([switch]$Rolling)

    $libraryPath = Join-Path $env:ProgramFiles "EqualizerAPO\config\ArtTuneDB\library"

    if (-not (Test-Path $libraryPath)) { return $null }

    $childItems = @(Get-ChildItem -Path $libraryPath -Recurse -File -ErrorAction SilentlyContinue)
    if ($childItems.Count -eq 0) { return $null }

    $docsFolder = [Environment]::GetFolderPath('MyDocuments')
    $backupRoot = Join-Path $docsFolder "Art Tune Backups"
    if ($Rolling) {
        # Single rolling dest -- overwrite any prior backup (no timestamped pile).
        $backupDest = Join-Path $backupRoot "library-previous"
    } else {
        $timestamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $backupDest = Join-Path $backupRoot "library-$timestamp"
    }

    Write-Host ""
    Write-Host "$($script:BoxMargin)Backing up ArtTuneDB library ($($childItems.Count) files)..." -ForegroundColor Cyan

    try {
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }
        if ($Rolling -and (Test-Path $backupDest)) {
            Remove-Item $backupDest -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -Path $libraryPath -Destination $backupDest -Recurse -Force
        Write-Host "$($script:BoxMargin)Library backed up to:" -ForegroundColor Green
        Write-Host "$($script:BoxMargin)$backupDest" -ForegroundColor DarkGray
        return $backupDest
    }
    catch {
        Write-Host "$($script:BoxMargin)Warning: Library backup failed: $_" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)Continuing with uninstall..." -ForegroundColor Yellow
        # $false, not $null: callers must be able to tell a FAILED backup from the two
        # "nothing to back up" cases above, which legitimately return $null.
        return $false
    }
}

function Backup-EAPOConfigFile {
    <#
    .SYNOPSIS
        Backs up config.txt alone, immediately before Write-InitialConfig overwrites it.
    .DESCRIPTION
        Write-InitialConfig always rewrites config.txt (Device: lines scope the
        includes that follow, so the order must be exact). That is fine as long as
        the previous file is never lost -- including for a non-ArtTune E-APO user
        whose own chain lives there.

        Only config.txt is copied, NOT the whole config folder: that folder holds
        the entire ArtTuneDB library and HeSuVi, and re-running Install is normal.

        Our own config self-identifies by its first line, so a re-run cannot bury
        the user's original under copies of our template:
          foreign config -> timestamped, kept permanently
          our config     -> single rolling copy, overwritten freely

        ONE foreign backup per run. Install-Eapo calls this before E-APO's setup runs,
        because a reinstall over an existing copy can replace config.txt; the later
        call from Write-InitialConfig would then timestamp whatever the installer left
        behind and present that to the user as "your existing config".
    .OUTPUTS
        Backup file path if one was taken, $null otherwise.
    #>
    $configFile = Join-Path $env:ProgramFiles "EqualizerAPO\config\config.txt"
    if (-not (Test-Path -LiteralPath $configFile)) { return $null }

    $isOurs = $false
    try {
        $firstLine = Get-Content -LiteralPath $configFile -TotalCount 1 -ErrorAction Stop
        $isOurs = ("$firstLine".Trim() -eq '# ArtTuneDB config.txt')
    } catch { } # Unreadable -- treat as foreign and keep it

    # Gated on foreign only. Our own config is a single rolling copy that costs nothing
    # to refresh, and refreshing it is correct: the second call runs immediately before
    # the overwrite, so it captures the newest version of our file.
    if (-not $isOurs -and $script:ForeignConfigBackup) { return $script:ForeignConfigBackup }

    $backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Art Tune Backups"
    if ($isOurs) {
        $backupDest = Join-Path $backupRoot "config-previous.txt"
    } else {
        $timestamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $backupDest = Join-Path $backupRoot "config-yours-$timestamp.txt"
    }

    try {
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }
        Copy-Item -LiteralPath $configFile -Destination $backupDest -Force

        if ($isOurs) {
            Write-Host "$($script:BoxMargin)Previous config.txt backed up." -ForegroundColor DarkGray
        } else {
            $script:ForeignConfigBackup = $backupDest
            Write-Host ""
            Write-Host "$($script:BoxMargin)Your existing E-APO config.txt was saved to:" -ForegroundColor Cyan
            Write-Host "$($script:BoxMargin)$backupDest" -ForegroundColor Cyan
            Write-Host "$($script:BoxMargin)ArtTune replaces config.txt with its own; yours is recoverable above." -ForegroundColor DarkGray
        }
        return $backupDest
    }
    catch {
        Write-Host "$($script:BoxMargin)Warning: config.txt backup failed: $_" -ForegroundColor Yellow
        return $null
    }
}

function Backup-EAPOConfig {
    <#
    .SYNOPSIS
        Backs up the entire E-APO config folder before destructive operations.
        Called from Uninstall-ExistingEAPO, where the whole tree is about to go.
        For the non-destructive config.txt rewrite, use Backup-EAPOConfigFile.
    .OUTPUTS
        Backup folder path if successful, $null otherwise.
    #>
    $configPath = Join-Path $env:ProgramFiles "EqualizerAPO\config"

    if (-not (Test-Path $configPath)) { return $null }

    $childItems = @(Get-ChildItem -Path $configPath -Recurse -File -ErrorAction SilentlyContinue)
    if ($childItems.Count -eq 0) { return $null }

    $docsFolder = [Environment]::GetFolderPath('MyDocuments')
    $timestamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $backupRoot = Join-Path $docsFolder "Art Tune Backups"
    $backupDest = Join-Path $backupRoot "eapo-config-$timestamp"

    Write-Host ""
    Write-Host "$($script:BoxMargin)Backing up E-APO config ($($childItems.Count) files)..." -ForegroundColor Cyan

    try {
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $configPath -Destination $backupDest -Recurse -Force
        Write-Host "$($script:BoxMargin)Config backed up to:" -ForegroundColor Green
        Write-Host "$($script:BoxMargin)$backupDest" -ForegroundColor DarkGray
        return $backupDest
    }
    catch {
        Write-Host "$($script:BoxMargin)Warning: Config backup failed: $_" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)Continuing with uninstall..." -ForegroundColor Yellow
        return $null
    }
}

function Test-ArtTuneKitInstalled {
    <#
    .SYNOPSIS
        Returns $true if the ArtTuneKit app is installed on this PC.
    .DESCRIPTION
        ArtTuneKit deploys the SAME versioned DLL and JSFX filenames to the SAME
        two folders this installer writes (VSTPlugins\ArtTuneKit and
        ReaPlugs\JS\Effects\ArtTuneKit), and neither product stamps provenance.
        So the plugins cannot be told apart file by file, and the only safe
        question is whether the app is here at all.

        The cost of the two errors is not symmetric. Saying "installed" when it
        is not just leaves our own plugins behind -- the state this uninstall had
        before. Saying "not installed" when it is deletes a working app's plugins
        out from under it. Every signal is therefore OR'd and any single hit wins.

        Four independent signals, in this order:
          1. Add/Remove Programs key -- authoritative, survives the app closed
          2. ProgramData library root -- survives the app closed
          3. Default install exe      -- survives the app closed
          4. Running process          -- proves presence, cannot prove absence

        Signal 1 is ArtTuneKit's own AppId (installer\ArtTuneKit.iss), the key its
        installer keys its own fresh-install detection on. All three hives are
        probed because PrivilegesRequiredOverridesAllowed lets it install per-user.
        Signal 3 only covers the default directory: the Inno directory page is not
        disabled, so a relocated install is invisible to it -- the same defect
        Test-VoicemeeterEdition avoids by keying presence on the registry.

        No try/catch anywhere: every probe below is already exception-safe via
        -ErrorAction SilentlyContinue, and empty catch blocks are a counted
        analyzer finding in this file.
    .OUTPUTS
        [bool]
    #>
    # 1. Add/Remove Programs. Inno Setup AppId, suffixed _is1 by Inno.
    $atkArpKey = '{2A2388E9-E5F3-46A3-AFB3-B26F33707564}_is1'
    foreach ($hive in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )) {
        if (Test-Path -LiteralPath (Join-Path $hive $atkArpKey) -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    # 2. Shared library root. Can outlive an uninstall, which errs toward
    # "installed" -- the safe direction here.
    if ($env:ProgramData) {
        if (Test-Path -LiteralPath (Join-Path $env:ProgramData "ArtTuneKit") -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    # 3. Default install directory, keyed on the exe rather than the folder so an
    # emptied leftover directory does not read as an install.
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        if (Test-Path -LiteralPath (Join-Path $root "ArtTuneKit\ArtTuneKit.exe") -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    # 4. Running process. Last because it is the only signal that goes away when
    # the user simply closes the app; it can confirm presence, never absence.
    if (@(Get-Process -Name 'ArtTuneKit' -ErrorAction SilentlyContinue).Count -gt 0) {
        return $true
    }

    return $false
}

function Uninstall-ExistingEAPO {
    <#
    .SYNOPSIS
        Removes an existing Equalizer APO installation with backup.
    .OUTPUTS
        'Removed' | 'NotFound' | 'Failed'
    #>
    $eapoPath = Join-Path $env:ProgramFiles "EqualizerAPO"
    $eapoUninstall = Join-Path $eapoPath "Uninstall.exe"

    if (-not (Test-Path $eapoPath)) {
        Write-Host "$($script:BoxMargin)No existing E-APO detected, proceeding." -ForegroundColor DarkGray
        return 'NotFound'
    }

    Write-Host "$($script:BoxMargin)Uninstalling E-APO..." -ForegroundColor Red

    # Kill LEQ Control Panel before device removal -- its COM audio callbacks
    # can crash if a third-party driver (e.g. Elgato) corrupts shared state
    # during audio subsystem destabilization (AccessViolationException).
    Stop-Process -Name "LEQControlPanel" -Force -ErrorAction SilentlyContinue
    Stop-EAPOEcosystemProcesses

    # Back up user data before destroying E-APO folder: the ArtTuneDB library
    # (dated, so squig.link EQs stay recoverable) AND the full E-APO config.
    $libraryPath = Join-Path $eapoPath "config\ArtTuneDB\library"
    $libraryFiles = @(Get-ChildItem -Path $libraryPath -Recurse -File -ErrorAction SilentlyContinue)
    if ($libraryFiles.Count -gt 0) {
        $null = Backup-ArtTuneLibrary
    }
    $null = Backup-EAPOConfig

    # Stop audio services first (E-APO hooks into them)
    Stop-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
    Stop-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction SilentlyContinue

    if (Test-Path $eapoUninstall) {
        try {
            $proc = Start-Process -FilePath $eapoUninstall -ArgumentList '/S', '/NORESTART', "_?=$eapoPath" -PassThru -WindowStyle Hidden
            $null = Write-Wait -Message "Removing E-APO..." -Until { $proc.HasExited } -TimeoutSeconds 30
            if (-not $proc.HasExited) {
                Write-Host "$($script:BoxMargin)Warning: E-APO uninstaller timed out, killing..." -ForegroundColor Yellow
                try { $proc.Kill() } catch { } # Process may have already exited
            }
        } catch {
            Write-Host "$($script:BoxMargin)Warning: E-APO uninstall failed: $_" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 3
    }

    # Kill stragglers and clean up
    Stop-Process -Name "EqualizerAPO*" -Force -ErrorAction SilentlyContinue
    # Kill audiodg to release file locks on E-APO DLLs -- required for folder deletion
    Stop-Process -Name "audiodg" -Force -ErrorAction SilentlyContinue

    Write-Wait -Message "Cleaning up E-APO files and registry..." -Until {
        Remove-Item $eapoPath -Recurse -Force -ErrorAction SilentlyContinue
        $childApoPath = "HKLM:\SOFTWARE\EqualizerAPO\Child APOs"
        if (Test-Path $childApoPath) {
            Remove-Item $childApoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        $eapoRegPath = "HKLM:\SOFTWARE\EqualizerAPO"
        if (Test-Path $eapoRegPath) {
            $subkeys = @(Get-ChildItem $eapoRegPath -ErrorAction SilentlyContinue)
            if (-not $subkeys -or $subkeys.Count -eq 0) {
                Remove-Item $eapoRegPath -Force -ErrorAction SilentlyContinue
            }
        }
        $true
    } -TimeoutSeconds 10 | Out-Null

    # Verify folder is actually gone -- uninstaller sometimes leaves remnants
    if (Test-Path $eapoPath) {
        Write-Host "$($script:BoxMargin)E-APO folder survived uninstall, force-removing..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
        Remove-Item $eapoPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $eapoPath) {
            Write-Host "$($script:BoxMargin)WARNING: Could not fully remove $eapoPath (files may be locked)." -ForegroundColor Yellow
        }
    }

    # -- ArtTuneKit plugins -------------------------------------------------
    # Deliberately here, and only here. This is inside the window opened by the
    # Stop-Service pair above: Audiosrv and AudioEndpointBuilder are down and
    # audiodg was killed before the E-APO delete, so nothing holds the DLLs.
    # E-APO loads them by absolute path out of a library tune file, never from
    # config.txt, so they outlive the config that referenced them.
    #
    # NOT gated on the E-APO tree delete above succeeding. A locked E-APO folder
    # and a locked plugin folder are separate failures and neither should mask
    # the other. Nothing below can throw or block the Start-Service that follows.
    #
    # ReaPlugs itself is NOT uninstalled -- not here, not anywhere. That is a
    # decision, not an oversight: it is a third-party suite the user may rely on
    # for their own work, and setup only ever adds an ArtTuneKit subfolder to it.
    # Only that subfolder goes. Same for VSTPlugins, which belongs to the user.
    $pluginDirs = @(
        (Join-Path $env:ProgramFiles "VSTPlugins\ArtTuneKit")
        (Join-Path $env:ProgramFiles "VSTPlugins\ReaPlugs\JS\Effects\ArtTuneKit")
    )
    $presentDirs = @($pluginDirs | Where-Object { Test-Path -LiteralPath $_ })

    if ($presentDirs.Count -gt 0) {
        if (Test-ArtTuneKitInstalled) {
            # DETECT AND SKIP. ArtTuneKit deploys the same versioned filenames to
            # these same folders, so there is no way to tell whose copy is whose.
            # Deleting here would pull the plugins out from under a working app.
            # Nothing is removed on this branch.
            $script:PluginRemoval.State = 'SkippedATK'
            Write-Host "$($script:BoxMargin)ArtTuneKit is installed and shares these plugins -- leaving them in place." -ForegroundColor DarkGray
            Write-Host "$($script:BoxMargin)Uninstalling ArtTuneKit from the app removes them." -ForegroundColor DarkGray
        } else {
            # Same retry idiom as the E-APO tree delete above: the removals run
            # inside the -Until block, so they are retried until the folders are
            # gone or the timeout expires.
            Write-Wait -Message "Removing ArtTuneKit plugins..." -Until {
                foreach ($pluginDir in $presentDirs) {
                    Remove-Item $pluginDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                @($presentDirs | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0
            } -TimeoutSeconds 10 | Out-Null

            $pluginSurvivors = @($presentDirs | Where-Object { Test-Path -LiteralPath $_ })
            if ($pluginSurvivors.Count -gt 0) {
                $script:PluginRemoval.State       = 'Failed'
                $script:PluginRemoval.FailedPaths = $pluginSurvivors
                Write-Host "$($script:BoxMargin)WARNING: could not remove the ArtTuneKit plugins:" -ForegroundColor Yellow
                foreach ($pluginDir in $pluginSurvivors) {
                    Write-Host "$($script:BoxMargin)  $pluginDir" -ForegroundColor Yellow
                }
                Write-Host "$($script:BoxMargin)Restart, then re-run setup and choose [4] to finish." -ForegroundColor DarkGray
            } else {
                $script:PluginRemoval.State = 'Removed'
                Write-Host "$($script:BoxMargin)ArtTuneKit plugins removed." -ForegroundColor Green
            }
        }
    }

    # Restart audio services
    Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 100
    Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
    $running = Write-Wait -Message "Waiting for Audiosrv" -Until {
        $svc = Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
        $svc -and $svc.Status -eq 'Running'
    } -TimeoutSeconds 15

    if (-not $running) {
        Write-Host "$($script:BoxMargin)Audio services not ready after E-APO uninstall, retrying..." -ForegroundColor Yellow
        Stop-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
        Stop-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
        $running = Write-Wait -Message "Waiting for Audiosrv (retry)" -Until {
            $svc = Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
            $svc -and $svc.Status -eq 'Running'
        } -TimeoutSeconds 15
    }

    # The retry result used to be discarded, so a permanently dead Audiosrv was
    # reported as a clean uninstall and the only cue was a timeout spinner line
    # already scrolled off screen. The removal DID happen either way, so the
    # return contract is unchanged -- only the message stops claiming a clean
    # finish that did not occur.
    if (-not $running) {
        Write-Host "$($script:BoxMargin)WARNING: Windows Audio did not restart after removing E-APO." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)E-APO itself was removed. Restart this PC to get audio back." -ForegroundColor Yellow
    } else {
        Write-Host "$($script:BoxMargin)E-APO uninstalled." -ForegroundColor Green
    }
    return 'Removed'
}

function Get-WaveLinkInfo {
    <#
    .SYNOPSIS
        Detects every installed Elgato Wave Link, across both packaging models.
    .DESCRIPTION
        Wave Link is a mixer this script does not own and cannot install. It is
        NOT a VB-Audio product, so Test-VoicemeeterEdition cannot see it -- yet a
        Wave Link user has the same reason to be spared an unrequested Voicemeeter
        as a Potato user does.

        Elgato CHANGED PACKAGING between major versions, so no single check finds
        both. Wave Link 3 ships as an MSIX/Store app: it is absent from the
        Uninstall registry hive and lives under WindowsApps, not Program Files.
        Wave Link 2 is a classic installer. They coexist happily -- both can be
        installed and running at once.

        Four independent signals, all evaluated (never stop at the first hit):
          1. MSIX/AppX package     -- the ONLY way to see Wave Link 3
          2. Add/Remove Programs   -- Wave Link 2, and carries its version
          3. Install directory     -- WaveLink.exe left by a broken/partial v2 uninstall
          4. Virtual audio devices -- catches an install whose other traces are gone
        Wave Link can be installed WITHOUT its audio driver, so signal 4 must never
        be the only check. Best-effort throughout; fails safe (a miss just means
        Voicemeeter installs as normal, and the user is still asked).
    .OUTPUTS
        Array of pscustomobject @{ Name; Version; Source }
    #>
    # Collect raw (version, source) hits from every signal, then dedupe by the
    # display label at the end. Two signals finding the same major version is
    # normal (v2 has both a registry entry and an install directory).
    $raw = @()

    # 1. MSIX / Store package -- Wave Link 3 exists ONLY here.
    try {
        $pkgs = @(Get-AppxPackage -Name 'Elgato.WaveLink' -ErrorAction SilentlyContinue)
        if ($pkgs.Count -eq 0) {
            $pkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                      Where-Object { Test-OrdinalContains "$($_.Name)" 'WaveLink' })
        }
        foreach ($pkg in $pkgs) {
            $raw += @{ Version = "$($pkg.Version)"; Source = 'MSIX' }
        }
    } catch { } # Appx module unavailable -- other signals still apply

    # 2. Add/Remove Programs -- Wave Link 2 and earlier.
    try {
        foreach ($hive in @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        )) {
            foreach ($entry in @(Get-ChildItem -Path $hive -ErrorAction SilentlyContinue |
                                 Where-Object { Test-OrdinalContains "$($_.GetValue('DisplayName'))" 'Wave Link' })) {
                $raw += @{ Version = "$($entry.GetValue('DisplayVersion'))"; Source = 'Registry' }
            }
        }
    } catch { }

    # 3. Install directory -- keyed on WaveLink.exe, NOT on the folder. Elgato's
    # uninstaller leaves the folder tree behind (empty subdirs, Licenses, Firmware),
    # so testing the directory reports a remnant as an install: it made the mixer
    # question appear on a PC with no Wave Link, and it pushed a version-less hit
    # that rendered as a dangling "v". Requiring the exe keeps what this signal is
    # for -- an install whose registry entry is gone but whose files still run --
    # while ignoring leftovers that cannot be launched.
    try {
        foreach ($dir in @(
            (Join-Path $env:ProgramFiles        "Elgato\WaveLink"),
            (Join-Path ${env:ProgramFiles(x86)} "Elgato\WaveLink")
        )) {
            if (-not $dir) { continue }
            $exe = Join-Path $dir "WaveLink.exe"
            if (Test-Path -LiteralPath $exe) {
                $raw += @{ Version = "$((Get-Item $exe).VersionInfo.ProductVersion)"; Source = 'Directory' }
            }
        }
    } catch { }

    # 4. Virtual audio devices -- only present when the driver was installed.
    try {
        $dev = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-OrdinalContains "$($_.Name)" 'Wave Link') -or
                (Test-OrdinalContains "$($_.Name)" 'Elgato Virtual')
            } |
            Select-Object -First 1
        if ($dev) { $raw += @{ Version = ''; Source = 'AudioDevice' } }
    } catch { }

    # Dedupe by display label (one entry per major version).
    $found = @()
    $seen  = @{}
    foreach ($hit in $raw) {
        $label = "Elgato Wave Link"
        if ($hit.Version -and ($hit.Version -match '^(\d+)')) {
            $label = "Elgato Wave Link $($Matches[1])"
        }
        if ($seen.ContainsKey($label)) { continue }
        $seen[$label] = $true
        $found += [pscustomobject]@{
            Name    = $label
            Version = $hit.Version
            Source  = $hit.Source
        }
    }

    return $found
}

function Get-InstalledMixers {
    <#
    .SYNOPSIS
        Inventory of audio mixers already on this PC that ArtTune did not install.
    .DESCRIPTION
        Detection decides WHAT TO ASK ABOUT, not whether to skip Voicemeeter. A
        product being installed does not prove the user relies on it -- Wave Link
        in particular is often installed alongside Elgato capture hardware and
        never used as a mixer, sometimes without its audio driver at all.

        Blocking marks a mixer that needs a second, explicit confirmation before
        Voicemeeter Standard is laid on top of it: all Voicemeeter editions share
        one folder, one uninstaller and one audio driver, so installing Standard
        over Banana/Potato can degrade the user's licensed copy. It is a warning
        gate, NOT a refusal -- the user is allowed to overrule it. Wave Link is a
        separate product and never gates.
    .OUTPUTS
        Array of pscustomobject @{ Kind; Name; Blocking }
    #>
    $mixers = @()

    # Only PAID editions gate. Banana/Potato share one folder and one uninstaller
    # with Standard, so laying Standard on top risks the user's licensed copy --
    # worth making them confirm it deliberately, but it is their call. Standard is
    # free and IS the thing we would install, so it never needs the extra warning.
    $vm = Test-VoicemeeterEdition
    if ($vm.Present) {
        $mixers += [pscustomobject]@{
            Kind     = 'Voicemeeter'
            Name     = $vm.Name
            Blocking = $vm.PaidPresent
        }
    }

    # Wave Link versions collapse into ONE question -- the decision is binary, so
    # asking separately about v2 and v3 would be two prompts to settle one thing.
    # Both are named so the user can recognise what was found.
    $wl = @(Get-WaveLinkInfo)
    if ($wl.Count -gt 0) {
        # Only NUMBERED labels become version tokens. Signals 3 and 4 can hit with no
        # readable version, which dedupes to a bare "Elgato Wave Link" -- blindly
        # rewriting that produced the empty token in "v2 and v". Unlabelled hits are
        # dropped from the list rather than printed as a dangling "v".
        $tokens = @($wl | ForEach-Object {
            $ver = Get-OrdinalMatchGroup "$($_.Name)" 'Wave Link\s+(\d+)$'
            if ($ver) { "v$ver" }
        } | Select-Object -Unique)

        if ($tokens.Count -eq 0) {
            $label = "Elgato Wave Link"
        } else {
            if ($tokens.Count -eq 1) {
                $joined = $tokens[0]
            } else {
                $joined = "$(($tokens[0..($tokens.Count - 2)]) -join ', ') and $($tokens[-1])"
            }
            $label = "Elgato Wave Link ($joined installed)"
        }
        $mixers += [pscustomobject]@{
            Kind     = 'WaveLink'
            Name     = $label
            Blocking = $false
        }
    }

    # Plain return, NOT ",$mixers": the comma idiom turns an empty array into a
    # one-element array holding an empty array, so a PC with no mixer would report
    # one and then fault on $mx.Name under StrictMode. Callers wrap in @().
    return $mixers
}

function Get-VoicemeeterFolder {
    <#
    .SYNOPSIS
        Resolves the folder Voicemeeter is actually installed in.
    .DESCRIPTION
        All editions share one folder, but that folder is not guaranteed to be the
        default: the installer honours a custom target and only the uninstall key
        records where it went. Asking the registry first means the exe probes in
        Test-VoicemeeterEdition look at the real install rather than a path we
        assumed, so "the exe is missing" means missing, not merely elsewhere.

        Every registry read is best-effort. InstallLocation and UninstallString are
        both optional values, and under StrictMode reading an absent property
        faults, so each is checked via PSObject.Properties before use.
    .OUTPUTS
        String path. Never null -- falls back to the x86 default.
    #>
    $vmRegKey = "VB:Voicemeeter {17359A74-1236-5467}"
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$vmRegKey",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$vmRegKey"
    )

    foreach ($rp in $regPaths) {
        $props = Get-ItemProperty -LiteralPath $rp -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        if ($props.PSObject.Properties['InstallLocation']) {
            $loc = "$($props.InstallLocation)".Trim().Trim('"')
            if ($loc -and (Test-Path -LiteralPath $loc -PathType Container)) { return $loc }
        }

        # UninstallString points at the setup exe INSIDE the install folder, so the
        # parent is the answer. Capture up to the first ".exe" to drop both the
        # surrounding quotes and any trailing switches (VB-Audio writes "... -u -h").
        if ($props.PSObject.Properties['UninstallString']) {
            $exe = Get-OrdinalMatchGroup "$($props.UninstallString)" '^\s*"?(.+?\.exe)'
            if ($exe) {
                $parent = Split-Path -Parent $exe
                if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) { return $parent }
            }
        }
    }

    # No usable registry hint. Prefer whichever default exists -- Invoke-FreshStart
    # treats the same pair as real locations when it cleans up.
    $defaults = @(
        (Join-Path "${env:ProgramFiles(x86)}" "VB\Voicemeeter"),
        (Join-Path "$env:ProgramFiles" "VB\Voicemeeter")
    )
    foreach ($d in $defaults) {
        if (Test-Path -LiteralPath $d -PathType Container) { return $d }
    }
    return $defaults[0]
}

function Test-VoicemeeterEdition {
    <#
    .SYNOPSIS
        Detects which Voicemeeter edition(s) are installed.
    .DESCRIPTION
        All editions share one folder (see Get-VoicemeeterFolder) and are told
        apart by their exe name. This script ONLY ever installs Standard (see
        $script:VoicemeeterUrlResolver), so the edition doubles as provenance:
        Banana or Potato present means the user installed it themselves.

        Two different notions of "installed" come out of this, and callers must
        pick the right one:

          Present    registry OR disk. Use for REMOVAL decisions -- a leftover
                     uninstall key with no exe still needs cleaning up.
          ExePresent disk only. Use for INSTALL decisions -- a leftover key is not
                     a working mixer, and skipping the install because of one
                     leaves the user with nothing.
          Standard   disk only, Standard specifically. The exact gate for "we
                     already have the thing we were about to install".
    .OUTPUTS
        pscustomobject @{ Present; ExePresent; Standard; Banana; Potato;
                          PaidPresent; Name; Folder; StandardExe }
    #>
    $vmFolder = Get-VoicemeeterFolder

    # Edition comes from the exe names (all editions share one folder).
    $standardExe = Join-Path $vmFolder "voicemeeter.exe"
    $standard = Test-Path -LiteralPath $standardExe
    $banana   = Test-Path -LiteralPath (Join-Path $vmFolder "voicemeeterpro.exe")
    $potato   = Test-Path -LiteralPath (Join-Path $vmFolder "voicemeeter8.exe")

    # PRESENCE also accepts the uninstall registry key -- the same signal
    # Uninstall-ExistingVoicemeeter and Add/Remove Programs use. A file-path check
    # alone would miss a non-default install location and wrongly conclude nothing
    # is installed, which is how the original VB-CABLE bug worked.
    $vmRegKey = "VB:Voicemeeter {17359A74-1236-5467}"
    $hasRegEntry = [bool](@(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$vmRegKey",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$vmRegKey"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1)

    # Name the most advanced edition present -- that is the one the user cares
    # about and the one whose uninstaller would run.
    $name = $null
    if ($potato)       { $name = "Voicemeeter Potato" }
    elseif ($banana)   { $name = "Voicemeeter Banana" }
    elseif ($standard) { $name = "Voicemeeter" }
    elseif ($hasRegEntry) { $name = "Voicemeeter" }   # registered, exe elsewhere

    return [pscustomobject]@{
        Present     = ($standard -or $banana -or $potato -or $hasRegEntry)
        ExePresent  = ($standard -or $banana -or $potato)
        Standard    = $standard
        Banana      = $banana
        Potato      = $potato
        PaidPresent = ($banana -or $potato)
        Name        = $name
        Folder      = $vmFolder
        StandardExe = $(if ($standard) { $standardExe } else { $null })
    }
}

function Uninstall-ExistingHiFiCable {
    <#
    .SYNOPSIS
        Removes the Hi-Fi Cable virtual audio driver and registry entries.
    #>
    # Primary detection: check uninstall registry keys (what Add/Remove Programs uses)
    $hifiRegKeys = $script:HiFiCableRegistryKeys
    $hasRegEntry = $hifiRegKeys | Where-Object { Test-Path $_ } | Select-Object -First 1

    # Fallback: check for audio devices
    $hasDevice = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-OrdinalContains "$($_.Name)" 'Hi-Fi') -or
            (Test-OrdinalContains "$($_.Name)" 'HiFi')
        }

    if (-not $hasRegEntry -and -not $hasDevice) {
        return 'NotFound'
    }

    # Find installer for uninstall (leftover setup EXEs are fine to use)
    $hifiPaths = @(
        "C:\Program Files (x86)\VB\ASIOBridge\HiFiCableAsioBridgeSetup.exe",
        "C:\Program Files\VB\CABLEHiFi\VBCABLE_Setup_x64.exe",
        "C:\Program Files\VB\CABLE\VBHIFI_Setup_x64.exe",
        "C:\Program Files (x86)\VB\CABLE\VBHIFI_Setup.exe"
    )
    $installer = $hifiPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    Write-Host "$($script:BoxMargin)Uninstalling Hi-Fi Cable..." -ForegroundColor Red

    if ($installer) {
        try {
            $proc = Start-Process -FilePath $installer -ArgumentList "-u -h" -PassThru -WindowStyle Hidden
            $null = Write-Wait -Message "Removing Hi-Fi Cable driver..." -Until { $proc.HasExited } -TimeoutSeconds 30
            if (-not $proc.HasExited) {
                Write-Host "$($script:BoxMargin)Warning: Hi-Fi Cable uninstaller timed out." -ForegroundColor Yellow
                try { $proc.Kill() } catch { } # Process may have already exited
            }
        } catch {
            Write-Host "$($script:BoxMargin)Warning: Hi-Fi Cable uninstall failed: $_" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 2
    }

    # Clean up files and registry
    Write-Wait -Message "Cleaning up Hi-Fi Cable files and registry..." -Until {
        # Hi-Fi-EXCLUSIVE folders: safe to remove whole.
        $hifiFolders = @(
            "C:\Program Files (x86)\VB\ASIOBridge",
            "C:\Program Files\VB\CABLEHiFi"
        )
        foreach ($folder in $hifiFolders) {
            if (Test-Path $folder) { Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue }
        }

        # SHARED with VB-CABLE -- Hi-Fi's setup exe can live here, but so does
        # VB-CABLE's own uninstaller (see Uninstall-ExistingVBCable). Removing the
        # directory would destroy VB-CABLE's only removal path. Delete Hi-Fi's own
        # files here, never the folder.
        $sharedFolders = @(
            "C:\Program Files\VB\CABLE",
            "C:\Program Files (x86)\VB\CABLE"
        )
        foreach ($folder in $sharedFolders) {
            if (-not (Test-Path $folder)) { continue }
            Get-ChildItem -Path $folder -Filter "VBHIFI_Setup*.exe" -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        }
        $hifiRegKeys = $script:HiFiCableRegistryKeys
        foreach ($regKey in $hifiRegKeys) {
            if (Test-Path $regKey) { Remove-Item -Path $regKey -Force -ErrorAction SilentlyContinue }
        }
        $uninstallHives = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($hive in $uninstallHives) {
            try {
                Get-ChildItem -Path $hive -ErrorAction SilentlyContinue |
                    Where-Object { Test-OrdinalMatch "$($_.Name)" 'VB:HiFi|Hi-Fi Cable|HiFiCable|VB:ASIOBridge|ASIO Bridge' } |
                    ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
            } catch { } # Registry cleanup is best-effort; leftover keys are harmless
        }
        $true
    } -TimeoutSeconds 10 | Out-Null

    # Clean up empty parent VB directories (only if nothing else remains, e.g. Voicemeeter)
    foreach ($vbParent in @("C:\Program Files\VB", "C:\Program Files (x86)\VB")) {
        if ((Test-Path $vbParent) -and
            @(Get-ChildItem -Path $vbParent -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -Path $vbParent -Force -ErrorAction SilentlyContinue
        }
    }

    # -- Nuclear cleanup: purge Hi-Fi Cable driver packages from the driver store --
    Write-Wait -Message "Purging Hi-Fi Cable from driver store..." -Until {
        try {
            # ONE predicate, used by both the per-block and the trailing-block path.
            # They were duplicated inline before; keeping two copies of a delete rule in
            # step by hand is exactly how a guard drifts. Culture-invariant throughout:
            # pnputil emits uppercase (OEM12.INF, VB-AUDIO), and under tr-TR raw -match
            # would fail every one of these -- silently no-opping the whole purge.
            #
            # The gate is an AND of two POSITIVE conditions, so a match failure can only
            # ever skip a delete, never widen one.
            $purgeBlock = {
                param($text)
                $oemInf = Get-OrdinalMatchGroup $text '(oem\d+\.inf)'
                if (-not $oemInf) { return }
                if ((Test-OrdinalMatch $text 'VB-Audio') -and
                    (Test-OrdinalMatch $text 'hifi|hi-fi|hfvaio|hfcable')) {
                    & pnputil /delete-driver $oemInf /force 2>&1 | Out-Null
                }
            }

            $pnpRaw = & pnputil /enum-drivers 2>&1
            # Split into per-driver blocks (separated by blank lines).
            # Field names are localized, but oem*.inf and product strings are not.
            $blockText = ""
            foreach ($line in $pnpRaw) {
                $trimmed = "$line".Trim()
                if ($trimmed -eq '' -and $blockText.Length -gt 0) {
                    & $purgeBlock $blockText
                    $blockText = ""
                    continue
                }
                $blockText += " $trimmed"
            }
            # Handle last block (no trailing blank line)
            if ($blockText.Length -gt 0) { & $purgeBlock $blockText }
        } catch { } # Best-effort; pnputil errors are non-fatal
        $true
    } -TimeoutSeconds 15 | Out-Null

    # -- Nuclear cleanup: remove phantom/ghost Hi-Fi Cable devices --
    Write-Wait -Message "Removing phantom Hi-Fi Cable devices..." -Until {
        try {
            $hifiDevices = Get-PnpDevice -ErrorAction SilentlyContinue |
                Where-Object {
                    # The Voicemeeter exclusion is the one NEGATIVE test in the Hi-Fi lane,
                    # so it is the one that fails OPEN when matching breaks. Culture-invariant
                    # here is what keeps it excluding on a tr-TR box.
                    ($_.Status -eq 'Error' -or $_.Status -eq 'Unknown') -and
                    (Test-OrdinalMatch "$($_.FriendlyName)" 'Hi-?Fi|HiFi') -and
                    -not (Test-OrdinalMatch "$($_.FriendlyName)" 'Voicemeeter')
                }
            foreach ($dev in $hifiDevices) {
                & pnputil /remove-device $dev.InstanceId 2>&1 | Out-Null
            }
        } catch { } # Best-effort
        $true
    } -TimeoutSeconds 15 | Out-Null

    # -- Nuclear cleanup: remove residual driver binaries from System32/SysWOW64 --
    # Patterns are HiFi-Cable-specific; Voicemeeter uses vbaudio_vmvaio*/vbvmaux*
    $hifiFilePatterns = @('vbaudio_hfvaio64*', 'vbaudio_hfcable*', 'vbhifi*')
    $systemDirs = @(
        (Join-Path $env:SystemRoot 'System32'),
        (Join-Path $env:SystemRoot 'System32\drivers'),
        (Join-Path $env:SystemRoot 'SysWOW64')
    )
    foreach ($dir in $systemDirs) {
        foreach ($pattern in $hifiFilePatterns) {
            Get-ChildItem -Path $dir -Filter $pattern -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    }

    # -- Conditional: remove VB-Audio certificate if no other VB-Audio products remain --
    # Must consider ALL Voicemeeter editions, not just Standard: a Potato-only box
    # has no voicemeeter.exe, and stripping the trusted-publisher cert there would
    # be wrong. VB-CABLE counts too -- it is a VB-Audio product using the same cert.
    $vmAny = (Test-VoicemeeterEdition).Present
    $vbCableEps = Get-ArtTuneEndpoints
    $vbCableAny = [bool]($vbCableEps.Render8 -or $vbCableEps.Render16 -or $vbCableEps.Capture)
    if (-not $vmAny -and -not $vbCableAny) {
        try {
            $thumbprint = '00859AAC6A54B8C1B3C139DE67846E64E7B82DB2'
            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
                'TrustedPublisher', 'LocalMachine')
            $store.Open('ReadWrite')
            $certs = $store.Certificates.Find(
                [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $thumbprint, $false)
            foreach ($c in $certs) { $store.Remove($c) }
            $store.Close()
        } catch { } # Best-effort
    }

    # Let Windows reconcile the device tree so cleanup is visible immediately
    & pnputil /scan-devices 2>&1 | Out-Null

    # Verify rather than assume. The cleanup above is thorough (registry, files,
    # driver store, phantom devices) but not guaranteed -- reporting success when
    # the device survives is what let earlier removal bugs stay invisible.
    # Culture-invariant deliberately: this is the verification, and it is reached via
    # the literal-path registry detection above, which is culture-proof. A locale that
    # broke this match would report 'Removed' for a driver still installed.
    $stillThere = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-OrdinalContains "$($_.Name)" 'Hi-Fi') -or
            (Test-OrdinalContains "$($_.Name)" 'HiFi')
        }
    if ($stillThere) {
        Write-Host "$($script:BoxMargin)Hi-Fi Cable is still present after removal." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)A restart usually clears it. If it persists, remove" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)'VB-Audio Hi-Fi Cable' from Device Manager." -ForegroundColor DarkGray
        return 'Failed'
    }

    Write-Host "$($script:BoxMargin)Hi-Fi Cable uninstalled." -ForegroundColor Green
    return 'Removed'
}

function Uninstall-ExistingVBCable {
    <#
    .SYNOPSIS
        Removes VB-CABLE via its own silent uninstaller (-u -h). Simple pattern:
        best-effort silent uninstall; the mandatory Start Clean reboot completes
        cleanup. NO pnputil / driver-store / registry surgery.
    .OUTPUTS
        'Removed'  - the uninstaller ran
        'NotFound' - VB-CABLE is not present
        'Failed'   - present, but it could not be removed (no uninstaller on disk,
                     or the uninstaller errored). NEVER reported as success: the
                     caller must surface the manual remedy.
    #>
    # Detection: the endpoints resolve (Get-ArtTuneEndpoints is strict about
    # 'VB-Audio Virtual Cable', so the retired Hi-Fi Cable cannot false-positive
    # here), or VB-CABLE's own setup exe is still on disk.
    $eps = Get-ArtTuneEndpoints
    $hasEndpoints = [bool]($eps.Render8 -or $eps.Render16 -or $eps.Capture)

    # Locate the installed VB-CABLE setup exe (fixed install location)
    $vbCablePaths = @(
        "C:\Program Files\VB\CABLE\VBCABLE_Setup_x64.exe",
        "C:\Program Files (x86)\VB\CABLE\VBCABLE_Setup_x64.exe",
        "C:\Program Files\VB\CABLE\VBCABLE_Setup.exe"
    )
    $installer = $vbCablePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $hasEndpoints -and -not $installer) {
        return 'NotFound'
    }

    Write-Host "$($script:BoxMargin)Uninstalling VB-CABLE..." -ForegroundColor Red

    if (-not $installer) {
        # No uninstaller on disk -- we cannot remove it. Do NOT download the pack
        # just to uninstall, and do NOT report success.
        Write-Host "$($script:BoxMargin)VB-CABLE setup exe not found; cannot remove it." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)To remove manually: download VBCABLE_Driver_Pack45, then run" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)  VBCABLE_Setup_x64.exe -u -h" -ForegroundColor DarkGray
        return 'Failed'
    }

    $ok = $true
    try {
        $proc = Start-Process -FilePath $installer -ArgumentList "-u -h" -PassThru -WindowStyle Hidden
        $null = Write-Wait -Message "Removing VB-CABLE driver..." -Until { $proc.HasExited } -TimeoutSeconds 30
        if (-not $proc.HasExited) {
            Write-Host "$($script:BoxMargin)Warning: VB-CABLE uninstaller timed out." -ForegroundColor Yellow
            try { $proc.Kill() } catch { } # Process may have already exited
            $ok = $false
        }
    } catch {
        Write-Host "$($script:BoxMargin)Warning: VB-CABLE uninstall failed: $_" -ForegroundColor Yellow
        $ok = $false
    }
    Start-Sleep -Seconds 2

    if (-not $ok) { return 'Failed' }

    Write-Host "$($script:BoxMargin)VB-CABLE removal complete." -ForegroundColor Green
    return 'Removed'
}

function Uninstall-ExistingVoicemeeter {
    <#
    .SYNOPSIS
        Removes Voicemeeter, its drivers, auto-start entries, and user data.
    .DESCRIPTION
        REFUSES to run when Banana or Potato is present. All editions share one
        folder and the uninstaller selection below prefers the most advanced one,
        so there is no way to surgically remove only the Standard copy this script
        installs -- the attempt would delete the user's own paid edition instead.
    .OUTPUTS
        'Removed' | 'NotFound' | 'Skipped' | 'Failed'
    #>
    $vmFolder = "${env:ProgramFiles(x86)}\VB\Voicemeeter"

    # Primary detection: check uninstall registry key (what Add/Remove Programs uses)
    $vmRegKey = "VB:Voicemeeter {17359A74-1236-5467}"
    $vmRegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$vmRegKey",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$vmRegKey"
    )
    $hasRegEntry = $vmRegPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $hasRegEntry) {
        return 'NotFound'
    }

    # Paid editions are never ours -- this script only installs Standard.
    $vm = Test-VoicemeeterEdition
    if ($vm.PaidPresent) {
        Write-Host "$($script:BoxMargin)$($vm.Name) detected -- leaving it alone." -ForegroundColor DarkGray
        Write-Host "$($script:BoxMargin)ArtTune does not install it, and the shared uninstaller would" -ForegroundColor DarkGray
        Write-Host "$($script:BoxMargin)remove your licensed edition. Use Add/Remove Programs if you" -ForegroundColor DarkGray
        Write-Host "$($script:BoxMargin)really want it gone." -ForegroundColor DarkGray
        return 'Skipped'
    }

    Write-Host "$($script:BoxMargin)Uninstalling Voicemeeter..." -ForegroundColor Red

    # Select the uninstaller. Only Standard can reach here (paid editions returned
    # 'Skipped' above), but keep the variant probes so the selection stays correct
    # if that guard is ever relaxed.
    $hasPotato = $vm.Potato
    $hasBanana = $vm.Banana

    $vmSetupPath = $null
    if ($hasPotato) {
        $candidate = Join-Path $vmFolder "Voicemeeter8Setup.exe"
        if (Test-Path $candidate) { $vmSetupPath = $candidate }
    }
    if (-not $vmSetupPath -and $hasBanana) {
        $candidate = Join-Path $vmFolder "VoicemeeterProSetup.exe"
        if (Test-Path $candidate) { $vmSetupPath = $candidate }
    }
    if (-not $vmSetupPath) {
        $candidate = Join-Path $vmFolder "voicemeetersetup.exe"
        if (Test-Path $candidate) { $vmSetupPath = $candidate }
    }

    # Step 1: Kill processes that hold audio handles
    Stop-AudioHoldingProcesses

    # Step 2: Run official uninstaller
    if ($vmSetupPath) {
        try {
            $proc = Start-Process -FilePath $vmSetupPath -ArgumentList "-u -h" -PassThru -WindowStyle Hidden
            $null = Write-Wait -Message "Removing Voicemeeter driver..." -Until { $proc.HasExited } -TimeoutSeconds 30
            if (-not $proc.HasExited) {
                try { $proc.Kill() } catch { } # Process may have already exited
            }
        } catch {
            Write-Host "$($script:BoxMargin)Warning: Voicemeeter uninstall failed: $_" -ForegroundColor Yellow
        }

        # Poll for registry key removal
        Write-Wait -Message "Waiting for Voicemeeter uninstaller to finish..." -Until {
            $regGone = $true
            foreach ($rp in $vmRegPaths) {
                if (Test-Path $rp) { $regGone = $false; break }
            }
            $regGone
        } -TimeoutSeconds 15 | Out-Null
    }

    # Clean up files, registry, and user data
    Write-Wait -Message "Cleaning up Voicemeeter files and registry..." -Until {
        # Force-delete install folders
        @("${env:ProgramFiles(x86)}\VB\Voicemeeter", "${env:ProgramFiles}\VB\Voicemeeter") | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }

        # Clean auto-start
        $startupFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
        @("Voicemeeter.lnk","VoicemeeterPro.lnk","Voicemeeter8.lnk") | ForEach-Object {
            $lnk = Join-Path $startupFolder $_
            if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
        }
        $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        @("VoiceMeeter","VoiceMeeterPro","VoiceMeeter8") | ForEach-Object {
            Remove-ItemProperty -Path $runKey -Name $_ -ErrorAction SilentlyContinue
        }

        # Clean HKCU registry
        @("HKCU:\VB-Audio","HKCU:\Software\VB-Audio") | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }

        # Clean HKLM uninstall
        foreach ($rp in $vmRegPaths) {
            if (Test-Path $rp) { Remove-Item $rp -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $uninstallHives = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($hive in $uninstallHives) {
            try {
                Get-ChildItem -Path $hive -ErrorAction SilentlyContinue |
                    Where-Object { Test-OrdinalMatch "$($_.Name)" 'VB:Voicemeeter|Voicemeeter' } |
                    ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
            } catch { } # Registry cleanup is best-effort; leftover keys are harmless
        }

        # Clean user data
        $vmDocs = Join-Path $env:USERPROFILE "Documents\Voicemeeter"
        if (Test-Path $vmDocs) { Remove-Item $vmDocs -Recurse -Force -ErrorAction SilentlyContinue }
        $vmXml = Join-Path $env:APPDATA "VoiceMeeterDefault.xml"
        if (Test-Path $vmXml) { Remove-Item $vmXml -Force -ErrorAction SilentlyContinue }
        $true
    } -TimeoutSeconds 15 | Out-Null

    Write-Host "$($script:BoxMargin)Voicemeeter uninstalled." -ForegroundColor Green
    return 'Removed'
}

function New-ContinueSetupShortcut {
    <#
    .SYNOPSIS
        Drops a "Continue ArtTune Setup" shortcut on the desktop before a reboot.
    .DESCRIPTION
        The script is delivered via 'irm ... | iex' and never persists, so after a
        restart the user has nothing to run. This is a bookmark, NOT auto-resume:
        no scheduled task, no state file, no persisted script. It just re-launches
        the same one-liner elevated.
    .OUTPUTS
        Shortcut path, or $null on failure (non-fatal).
    #>
    try {
        $desktop  = [Environment]::GetFolderPath('Desktop')
        $lnkPath  = Join-Path $desktop "Continue ArtTune Setup.lnk"
        $command  = "irm artiswar.io/tools/ArtTuneGuided | iex"
        $encoded  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
        $lnk.IconLocation = "$env:SystemRoot\System32\shell32.dll,165"
        $lnk.Description  = "Finish installing the ArtIsWar audio stack"
        $lnk.Save()

        # Mark it run-as-administrator (byte 21 of the link flags block).
        $bytes = [System.IO.File]::ReadAllBytes($lnkPath)
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($lnkPath, $bytes)

        return $lnkPath
    } catch {
        # Non-fatal: the on-screen command is still shown.
        return $null
    }
}

function Remove-ArtTuneDesktopShortcuts {
    <#
    .SYNOPSIS
        Deletes the desktop icons setup created (uninstall-everything only).
    .DESCRIPTION
        Both icons are ArtTune's own and neither outlives a full uninstall as
        anything but a dead shortcut: ArtTuneDB.lnk targets the E-APO config tree
        the wipe destroys, and "Continue ArtTune Setup" is a leftover bookmark
        from a [2] Start Clean run that has nothing left to continue.

        The all-users desktop is swept alongside the current one. Setup only ever
        writes to the per-user desktop, but a copy dragged there by hand is still
        an ArtTune icon the user expects gone.
    .OUTPUTS
        pscustomobject @{ Removed; Failed } -- display names / full paths.
    #>
    $shortcuts = @(
        @{ File = "ArtTuneDB.lnk";              Name = "ArtTuneDB desktop icon" }
        @{ File = "Continue ArtTune Setup.lnk"; Name = "Continue ArtTune Setup icon" }
    )
    $desktops = @(
        [Environment]::GetFolderPath('Desktop')
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    ) | Where-Object { $_ } | Select-Object -Unique

    $removed = @(); $failed = @()
    foreach ($desktop in $desktops) {
        foreach ($sc in $shortcuts) {
            $lnk = Join-Path $desktop $sc.File
            if (-not (Test-Path -LiteralPath $lnk)) { continue }
            # A read-only/hidden .lnk survives a plain Remove-Item, and
            # -ErrorAction SilentlyContinue would report that as a success. Clear
            # the attributes first, then confirm the file is actually gone.
            try {
                (Get-Item -LiteralPath $lnk -Force).Attributes = [System.IO.FileAttributes]::Normal
            } catch { }   # Best effort -- the delete below is the real test
            Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $lnk) { $failed += $lnk } else { $removed += $sc.Name }
        }
    }

    return [pscustomobject]@{
        Removed = @($removed | Select-Object -Unique)
        Failed  = @($failed)
    }
}

function Invoke-FreshStart {
    <#
    .SYNOPSIS
        Uninstalls the ArtTune audio stack in order.
    .DESCRIPTION
        Voicemeeter is NOT part of the wipe. A clean ArtTune install has no
        business deleting the user's mixer, and the paid editions are never ours.
        The uninstall-everything flow opts in explicitly via -IncludeVoicemeeter.
    .PARAMETER PromptRestart
        If true, prompts user to restart after uninstalling (default: true).
    .PARAMETER IncludeVoicemeeter
        Also attempt Voicemeeter removal. Paid editions are still refused inside
        Uninstall-ExistingVoicemeeter.
    .OUTPUTS
        pscustomobject @{ Removed; Failed; Skipped } -- arrays of component names.
    #>
    param(
        [bool]$PromptRestart = $true,
        [switch]$IncludeVoicemeeter
    )

    Write-Host ""
    Write-Host "$($script:BoxMargin)Removing the existing audio stack..." -ForegroundColor Red

    # Kill LEQ Control Panel before device removal -- its COM audio callbacks
    # can crash if a third-party driver (e.g. Elgato) corrupts shared state
    # during audio subsystem destabilization (AccessViolationException).
    Stop-Process -Name "LEQControlPanel" -Force -ErrorAction SilentlyContinue
    Stop-EAPOEcosystemProcesses

    # Detect what's installed before doing anything
    $hasEapo = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO")
    $hasHifi = ($script:HiFiCableRegistryKeys | Where-Object { Test-Path $_ } | Select-Object -First 1) -or
        (Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-OrdinalContains "$($_.Name)" 'Hi-Fi') -or
                (Test-OrdinalContains "$($_.Name)" 'HiFi')
            })
    $hasVm = $false
    if ($IncludeVoicemeeter) {
        $hasVm = (Test-VoicemeeterEdition).Present
    }
    # VB-CABLE: positive endpoint check. A name match on *VB-Audio* would also
    # match the retired Hi-Fi Cable and claim VB-CABLE was present when it is not.
    $vbEps = Get-ArtTuneEndpoints
    $hasVbCable = [bool]($vbEps.Render8 -or $vbEps.Render16 -or $vbEps.Capture)

    if (-not $hasEapo -and -not $hasHifi -and -not $hasVm -and -not $hasVbCable) {
        Write-Host "$($script:BoxMargin)Nothing to remove -- this PC is already clean." -ForegroundColor Green
        Write-Host "$($script:BoxMargin)Choose [1] Install to set up the audio stack." -ForegroundColor DarkGray
        return [pscustomobject]@{ Removed = @(); Failed = @(); Skipped = @() }
    }

    Write-Host ""
    $toRemove = @()
    if ($hasVbCable) { $toRemove += "VB-CABLE" }
    if ($hasHifi)    { $toRemove += "Hi-Fi Cable" }
    if ($hasEapo)    { $toRemove += "E-APO + HeSuVi" }
    if ($hasVm)      { $toRemove += "Voicemeeter" }
    Write-Host "$($script:BoxMargin)This will remove: $($toRemove -join ', ')" -ForegroundColor Yellow
    Write-Host "$($script:BoxMargin)Your E-APO config and ArtTuneDB library (including any squig.link EQs)" -ForegroundColor Yellow
    Write-Host "$($script:BoxMargin)are backed up first to Documents\Art Tune Backups\." -ForegroundColor Yellow
    Write-Host "$($script:BoxMargin)A restart afterward finishes clearing the drivers." -ForegroundColor Yellow
    Write-Host ""

    # Order matters: Hi-Fi cleanup used to delete VB-CABLE's directory (and with it
    # VB-CABLE's only uninstaller). That is fixed in Uninstall-ExistingHiFiCable,
    # but removing VB-CABLE first keeps the dependency out of the ordering entirely.
    $removed = @(); $failed = @(); $skipped = @()
    $steps = @(
        @{ Name = "VB-CABLE";       Action = { Uninstall-ExistingVBCable } }
        @{ Name = "Hi-Fi Cable";    Action = { Uninstall-ExistingHiFiCable } }
        @{ Name = "E-APO + HeSuVi"; Action = { Uninstall-ExistingEAPO } }
    )
    if ($IncludeVoicemeeter) {
        $steps += @{ Name = "Voicemeeter"; Action = { Uninstall-ExistingVoicemeeter } }
    }
    foreach ($step in $steps) {
        switch (& $step.Action) {
            'Removed' { $removed += $step.Name }
            'Failed'  { $failed  += $step.Name }
            'Skipped' { $skipped += $step.Name }
            default   { }   # NotFound -- nothing to report
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "$($script:BoxMargin)Could not remove: $($failed -join ', ')" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)A restart clears most leftovers. If one persists, remove it from" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)Device Manager or Add/Remove Programs before running Install." -ForegroundColor DarkGray
    }

    if ($removed.Count -gt 0) {
        if ($PromptRestart) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)Removed: $($removed -join ', ')" -ForegroundColor Green
            Write-Host ""
            Write-Host "$($script:BoxMargin)Your old config and library were backed up to Documents\Art Tune Backups\." -ForegroundColor DarkGray
            Write-Host "$($script:BoxMargin)Old squig.link combos are recoverable there via the ArtTuneDB desktop shortcut." -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "$($script:BoxMargin)A restart is required to finish removing drivers." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)After restarting, re-run this script and choose [1] Install:" -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)  irm artiswar.io/tools/ArtTuneGuided | iex" -ForegroundColor Cyan
            Write-Host "$($script:BoxMargin)(a 'Continue ArtTune Setup' shortcut has been placed on your desktop)." -ForegroundColor DarkGray
            $null = New-ContinueSetupShortcut
            Write-Host ""
            Write-Host "$($script:BoxMargin)Restart now? [Y/n]: " -ForegroundColor Yellow -NoNewline
            $restart = Read-Host
            if ($restart -eq 'n' -or $restart -eq 'N') {
                Write-Host ""
                Write-Host "$($script:BoxMargin)OK -- restart manually before re-running this script." -ForegroundColor DarkGray
                Write-Host ""
                exit 0
            }
            Restart-Computer -Force
        }
    }

    return [pscustomobject]@{ Removed = $removed; Failed = $failed; Skipped = $skipped }
}

function Uninstall-SoundControl {
    <#
    .SYNOPSIS
        Removes LEQ Control Panel (PATH C only).
    #>
    $scFolder = Join-Path $env:LOCALAPPDATA "Programs\LEQControlPanel"
    $scLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "LEQ Control Panel.lnk"

    if (-not (Test-Path $scFolder)) {
        return $false
    }

    Write-Host "$($script:BoxMargin)Uninstalling LEQ Control Panel..." -ForegroundColor Red

    # Kill process
    Stop-Process -Name "LEQControlPanel" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    # Remove Run key
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "LEQControlPanel" -ErrorAction SilentlyContinue

    # Remove desktop shortcut
    if (Test-Path $scLnk) { Remove-Item $scLnk -Force -ErrorAction SilentlyContinue }

    # Delete folder
    Remove-Item $scFolder -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "$($script:BoxMargin)LEQ Control Panel uninstalled." -ForegroundColor Green
    return $true
}

# ============================================================================
# SECTION 5: Install Functions
# ============================================================================

function Install-VBAudioCertificate {
    <#
    .SYNOPSIS
        Pre-trusts the VB-Audio driver signing certificate so Windows
        skips the driver installation confirmation dialog.
    #>

    try {
        $thumbprint = '00859AAC6A54B8C1B3C139DE67846E64E7B82DB2'

        # Check if already trusted
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            'TrustedPublisher', 'LocalMachine')
        try {
            $store.Open('ReadOnly')
            $existing = $store.Certificates.Find(
                [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $thumbprint, $false)
            if ($existing.Count -gt 0) { return $true }
        }
        finally { $store.Close() }

        # VB-Audio driver signing certificate (CN=Vincent Burel, Digital ID Class 3)
        # Extracted from vbaudio_hfvaio64_win7.sys -- public cert embedded in every
        # copy of the Hi-Fi Cable / Voicemeeter driver package.
        $certBase64 = 'MIIFijCCBHKgAwIBAgIQB6z1xadU2q9M1r0ddHkdWTANBgkqhki' +
            'G9w0BAQUFADCBtDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDlZlcmlTaWduLC' +
            'BJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTswOQYDV' +
            'QQLEzJUZXJtcyBvZiB1c2UgYXQgaHR0cHM6Ly93d3cudmVyaXNpZ24uY29' +
            'tL3JwYSAoYykxMDEuMCwGA1UEAxMlVmVyaVNpZ24gQ2xhc3MgMyBDb2RlI' +
            'FNpZ25pbmcgMjAxMCBDQTAeFw0xMzExMDIwMDAwMDBaFw0xNTAxMDEyMzU5' +
            'NTlaMIHNMQswCQYDVQQGEwJGUjERMA8GA1UECBMIRG9yZG9nbmUxDjAMBgN' +
            'VBAcTBUV5bWV0MSQwIgYDVQQKFBtObyBPcmdhbml6YXRpb24gQWZmaWxpYX' +
            'Rpb24xPjA8BgNVBAsTNURpZ2l0YWwgSUQgQ2xhc3MgMyAtIE1pY3Jvc29md' +
            'CBTb2Z0d2FyZSBWYWxpZGF0aW9uIHYyMR0wGwYDVQQLFBRJbmRpdmlkdWF' +
            'sIERldmVsb3BlcjEWMBQGA1UEAxQNVmluY2VudCBCdXJlbDCCASIwDQYJKo' +
            'ZIhvcNAQEBBQADggEPADCCAQoCggEBAOYiZUittitgZENWdXIYRoqi2HUKqYJ' +
            'b2CA6gRGkJ5VPdv5qMUly6C8tLxlbomX/V3GyWUTN8ZojFU7RWODhVbXkAD' +
            'kwh2eXP6CsmED2SEXFVE5+G5Hf/jFScYYw7wmGkgIQHiYPkWZLEY85Y1Etg' +
            'HEB3rA+sT+cGAPr3X8QJZmdxME6s5SXb2hl9KkiuGpjQR8XEESmHUSft2Ip' +
            'SOz91ocWZIn9k1s9wWph2q5hJjNMtd7IO7m5D7k1MYghzKnZpZGq9rLgDyd' +
            'pnag9LdrR++pYx5WqNkbCqwXeE8PSYW8BvMNne8ZD4oVW4nUC6S6jcPvNe/' +
            'JAUy/rLNmSBn1IQECAwEAAaOCAXswggF3MAkGA1UdEwQCMAAwDgYDVR0PAQH' +
            '/BAQDAgeAMEAGA1UdHwQ5MDcwNaAzoDGGL2h0dHA6Ly9jc2MzLTIwMTAtY3' +
            'JsLnZlcmlzaWduLmNvbS9DU0MzLTIwMTAuY3JsMEQGA1UdIAQ9MDswOQYLY' +
            'IZIAYb4RQEHFwMwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cudmVyaXNp' +
            'Z24uY29tL3JwYTATBgNVHSUEDDAKBggrBgEFBQcDAzBxBggrBgEFBQcBAQR' +
            'lMGMwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLnZlcmlzaWduLmNvbTA7Bg' +
            'grBgEFBQcwAoYvaHR0cDovL2NzYzMtMjAxMC1haWEudmVyaXNpZ24uY29tL' +
            '0NTQzMtMjAxMC5jZXIwHwYDVR0jBBgwFoAUz5mp6nsm9EvJjo/X8AUm7+PS' +
            'p50wEQYJYIZIAYb4QgEBBAQDAgQQMBYGCisGAQQBgjcCARsECDAGAQEAAQH' +
            '/MA0GCSqGSIb3DQEBBQUAA4IBAQADlID7V7ye/9ibIHcTo08u9XP/vbrkk7+G' +
            't6k2gZjXLZEs2Q8Bv53sY1xSTmBg8HRZc1CuOR2G2cYSVD8S5NPPYx/6TES' +
            'GuHMTGG2a31G8EHDLUgSRCZmpyfiJAC98iXrIuDWJ1zEXj8f0+cktENiayH2' +
            'hrVgOlxAjvgZ7zpzg+T291f8wwXg2BXVRmXr6SNeLBNX5QsjzK3bsOkjGeE' +
            'fu47CV2CWuAFQW1Yt9HuE64v6h96Z3zipddcg3vHqE81w7JTFrvU7D77iOEz' +
            'ei8RxaUTLhrureghtB7UEymvU5T7PJivdZ51k81+hYBR0Y1JpIsF6YOUcrMe' +
            'BCO5vjYn0Y'

        $certBytes = [Convert]::FromBase64String($certBase64)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)

        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            'TrustedPublisher', 'LocalMachine')
        $store.Open('ReadWrite')
        $store.Add($cert)
        $store.Close()

        return $true
    }
    catch {
        return $false
    }
}

function Install-VBCable {
    <#
    .SYNOPSIS
        Extracts and installs the VB-CABLE v45 virtual audio driver from the
        VBCABLE_Driver_Pack45 ZIP. WAITS for the installer's NATURAL exit -- the
        driver finalizes endpoint naming/icons on shutdown, so it is never killed
        early. A non-zero exit means a prior VB-CABLE version is present; the -u -h
        uninstall remedy is surfaced.
    #>
    param([ValidateNotNullOrEmpty()][string]$ZipPath)

    Write-Host "$($script:BoxMargin)Installing VB-CABLE..." -ForegroundColor Cyan

    # Extract ZIP
    $extractPath = Join-Path $script:TempPath "VBCable_Extract"
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force

    # Find the x64 setup exe
    $setupExe = Get-ChildItem -LiteralPath $extractPath -Filter "VBCABLE_Setup_x64.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $setupExe) {
        $setupExe = Get-ChildItem -LiteralPath $extractPath -Filter "VBCABLE_Setup*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $setupExe) {
        Write-Host "$($script:BoxMargin)ERROR: VB-CABLE setup exe not found in archive." -ForegroundColor Red
        return $false
    }

    # Pre-trust VB-Audio driver certificate (suppresses driver confirmation dialog)
    $null = Install-VBAudioCertificate

    # Run silent install (-i install, -h hidden). Wait for NATURAL exit; never kill.
    $proc = Start-Process -FilePath $setupExe.FullName -ArgumentList "-i -h" -PassThru -ErrorAction Stop
    Write-Wait -Message "Installing VB-CABLE driver (waiting for it to finish)..." -Until { $proc.HasExited } -TimeoutSeconds 180 | Out-Null
    # Guarantee full exit before endpoint detection runs -- killing early races the
    # driver's endpoint naming/icon finalization.
    $proc.WaitForExit()
    Start-Sleep -Seconds 2
    $exit = $proc.ExitCode

    # Cleanup extract folder
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

    if ($exit -ne 0) {
        Write-Host "$($script:BoxMargin)VB-CABLE setup returned exit code $exit." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)A previous VB-CABLE version may already be present." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)To fully reinstall: run the setup with '-u -h' to uninstall, reboot, then re-run:" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)  VBCABLE_Setup_x64.exe -u -h" -ForegroundColor DarkGray
        # Non-fatal: endpoints from the existing cable can still be configured, so the
        # run deliberately continues from here. The return reports the failure anyway,
        # so the completion summary does not show a tick for a setup that errored.
        return $false
    }

    Write-Host "$($script:BoxMargin)VB-CABLE installed." -ForegroundColor Green
    return $true
}

function Install-Voicemeeter {
    <#
    .SYNOPSIS
        Extracts and installs Voicemeeter Standard from a ZIP archive.
    #>
    param([ValidateNotNullOrEmpty()][string]$ZipPath)

    Write-Host "$($script:BoxMargin)Installing Voicemeeter..." -ForegroundColor Cyan

    # Resolved rather than hardcoded, so this agrees with the skip decision in
    # Get-Downloads -- both ask Test-VoicemeeterEdition where Voicemeeter lives.
    if ((Test-VoicemeeterEdition).Standard) {
        Write-Host "$($script:BoxMargin)Voicemeeter already installed." -ForegroundColor Green
        return $true
    }

    # Extract ZIP
    $extractPath = Join-Path $script:TempPath "Voicemeeter_Extract"
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force

    # Find setup exe
    $setupExe = Get-ChildItem -LiteralPath $extractPath -Filter "*Setup*.exe" -Recurse -ErrorAction Stop | Select-Object -First 1
    if (-not $setupExe) {
        Write-Host "$($script:BoxMargin)ERROR: Voicemeeter setup exe not found in archive." -ForegroundColor Red
        return $false
    }

    # Pre-trust VB-Audio driver certificate (suppresses driver confirmation dialog)
    $null = Install-VBAudioCertificate

    # Run silent install
    $proc = Start-Process -FilePath $setupExe.FullName -ArgumentList "-i -h" -PassThru -ErrorAction Stop
    Write-Wait -Message "Installing Voicemeeter driver..." -Until { $proc.HasExited } -TimeoutSeconds 60 | Out-Null
    Start-Sleep -Seconds 2

    # Verify. Re-probe instead of reusing a pre-install path: setup picks its own
    # target folder, and that is exactly what Test-VoicemeeterEdition resolves.
    if (-not (Test-VoicemeeterEdition).Standard) {
        Write-Host "$($script:BoxMargin)WARNING: Voicemeeter verification failed." -ForegroundColor Yellow
        return $false
    }

    # Cleanup extract folder
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "$($script:BoxMargin)Voicemeeter installed." -ForegroundColor Green
    return $true
}

function Install-ReaPlugs {
    <#
    .SYNOPSIS
        Installs the ReaPlugs VST plugin suite and brings the NSIS dialog to the foreground.
    #>
    param([ValidateNotNullOrEmpty()][string]$InstallerPath)

    Write-Host "$($script:BoxMargin)Installing ReaPlugs..." -ForegroundColor Cyan

    $verifyDir = "${env:ProgramFiles}\VSTPlugins\ReaPlugs"
    $dlls = @(Get-ChildItem "$verifyDir\*.dll" -ErrorAction SilentlyContinue)
    if ($dlls.Count -ge 5) {
        Write-Host "$($script:BoxMargin)ReaPlugs already installed ($($dlls.Count) DLLs)." -ForegroundColor Green
        return $true
    }

    Unblock-File -LiteralPath $InstallerPath -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -PassThru -ErrorAction Stop

    # Poll for the ReaPlugs "installed" dialog and bring it to front
    $focusJob = Start-Job -ScriptBlock {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinHelper2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
'@
        for ($i = 0; $i -lt 60; $i++) {
            $callback = [WinHelper2+EnumWindowsProc]{
                param($hwnd, $lParam)
                $sb = New-Object System.Text.StringBuilder 256
                [WinHelper2]::GetWindowText($hwnd, $sb, 256) | Out-Null
                $t = $sb.ToString()
                if ($t -and ($t -like "*ReaPlug*" -or $t -like "*NSIS*" -or $t -like "*reaplugs*")) {
                    [WinHelper2]::ShowWindow($hwnd, 5) | Out-Null
                    [WinHelper2]::SetForegroundWindow($hwnd) | Out-Null
                    return $false
                }
                return $true
            }
            [WinHelper2]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
            Start-Sleep -Milliseconds 500
        }
    }

    Write-ActionBox -Lines @(
        "ReaPlugs installer is running.",
        "",
        "  -> Click OK when it says 'installed'",
        "",
        "Press Enter here when done."
    )

    Stop-Job $focusJob -ErrorAction SilentlyContinue
    Remove-Job $focusJob -Force -ErrorAction SilentlyContinue

    # Wait for installer if it hasn't finished
    if (-not $proc.HasExited) {
        Write-Wait -Message "Finishing ReaPlugs installation..." -Until { $proc.HasExited } -TimeoutSeconds 60 | Out-Null
    }

    # Verify
    $dlls = @(Get-ChildItem "$verifyDir\*.dll" -ErrorAction SilentlyContinue)
    if ($dlls.Count -lt 5) {
        Write-Host "$($script:BoxMargin)WARNING: ReaPlugs verification failed (found $($dlls.Count) DLLs, expected 5+)." -ForegroundColor Yellow
        return $false
    }

    Write-Host "$($script:BoxMargin)ReaPlugs installed ($($dlls.Count) DLLs)." -ForegroundColor Green
    return $true
}

function Get-EapoInstallPath {
    <#
    .SYNOPSIS
        The folder Equalizer APO records as its own install location, or $null.
    .DESCRIPTION
        HKLM:\SOFTWARE\EqualizerAPO\InstallPath is written by E-APO's own setup and is
        what that setup reads back when it runs again -- so it, not a Test-Path on the
        default folder, is what decides where a REINSTALL lands. Install-Eapo uses it
        both to spot a non-default install up front and to verify where setup actually
        went, rather than assuming /D= won.

        Returned even when the folder no longer exists: a stale key still steers the
        installer, so callers that care about a live install Test-Path it themselves.

        StrictMode-safe: the key exists on machines where the value does not.
    #>
    foreach ($rp in @('HKLM:\SOFTWARE\EqualizerAPO', 'HKLM:\SOFTWARE\WOW6432Node\EqualizerAPO')) {
        $props = Get-ItemProperty -LiteralPath $rp -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        if (-not $props.PSObject.Properties['InstallPath']) { continue }
        $p = "$($props.InstallPath)".Trim().Trim('"')
        if ($p) { return $p.TrimEnd('\', '/') }
    }
    return $null
}

function Install-Eapo {
    <#
    .SYNOPSIS
        Installs Equalizer APO and creates the ArtTuneDB folder structure.
    .DESCRIPTION
        ALWAYS runs the installer, including over an existing E-APO. That is the point:
        setup is the only thing that reopens Device Selector, and [1] Install has just
        removed the retired Hi-Fi Cable that an existing E-APO was very likely bound to.
        Everything after the installer -- the ArtTuneDB folder, its icon, its .url files
        and the desktop shortcut -- used to be unreachable on a machine that already had
        E-APO, because the whole function was skipped.
    #>
    param([ValidateNotNullOrEmpty()][string]$InstallerPath)

    Write-Host "$($script:BoxMargin)Installing Equalizer APO..." -ForegroundColor Cyan

    # Every path downstream -- config.txt, the ArtTuneDB library root, HeSuVi, the HRIR,
    # the uninstall lane -- is pinned to ProgramFiles\EqualizerAPO, so that is the only
    # location this script can drive. /D= is the lever for it.
    $eapoRoot   = (Join-Path $env:ProgramFiles "EqualizerAPO").TrimEnd('\')
    $eapoConfig = Join-Path $eapoRoot "config"

    # A non-default existing install is the one case /D= may lose: E-APO's setup reads
    # its own recorded path back. Say so before the dialogs appear rather than leaving
    # the user to wonder why the verification below failed.
    $priorRoot = Get-EapoInstallPath
    $priorIsCustom = ($priorRoot -and
        -not [string]::Equals($priorRoot, $eapoRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $priorRoot -PathType Container))
    if ($priorIsCustom) {
        Write-Host ""
        Write-Host "$($script:BoxMargin)Equalizer APO is installed in a non-default folder:" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)  $priorRoot" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)ArtTune only drives the default location. Setup will aim for" -ForegroundColor DarkGray
        Write-Host "$($script:BoxMargin)  $eapoRoot" -ForegroundColor DarkGray
        Write-Host "$($script:BoxMargin)and check where it actually landed afterwards." -ForegroundColor DarkGray
        Write-Host ""
    }

    # config.txt is the user's, and a reinstall can replace it -- so the backup happens
    # HERE, before setup runs, not only in Write-InitialConfig. Backup-EAPOConfigFile
    # keeps one foreign copy per run, so its later call cannot bury this one under
    # whatever the installer left behind.
    $null = Backup-EAPOConfigFile

    # Peace / HeSuVi / Editor hold file locks on E-APO's DLLs and would make an
    # install-over fail in place. No-ops on a machine with no E-APO yet.
    Stop-EAPOEcosystemProcesses

    Unblock-File -LiteralPath $InstallerPath -ErrorAction SilentlyContinue
    # /S is semi-silent (the Device Selector dialog still appears). /D sets the install
    # dir (matches ATK app: InstallEapoFromFileAsync) and NSIS requires it LAST and
    # UNQUOTED -- everything after /D= is read verbatim to end of line. That is why this
    # stays ONE argument string: an array would quote the path and break it.
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList "/S /D=$eapoRoot" -PassThru -ErrorAction Stop

    # Start a background job to poll for E-APO dialog windows and bring them to front.
    # The installer spawns Device Selector, Upgrades, Testing APO, and Info dialogs --
    # with /S mode the main process has no window, so Set-WindowForeground won't work.
    $focusJob = Start-Job -ScriptBlock {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinHelper {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
'@
        $titles = @("Device Selector", "Upgrades available", "Testing APO", "Info", "Equalizer APO Setup")
        for ($i = 0; $i -lt 120; $i++) {
            foreach ($title in $titles) {
                $callback = [WinHelper+EnumWindowsProc]{
                    param($hwnd, $lParam)
                    $sb = New-Object System.Text.StringBuilder 256
                    [WinHelper]::GetWindowText($hwnd, $sb, 256) | Out-Null
                    $t = $sb.ToString()
                    if ($t -and $t -like "*$title*") {
                        [WinHelper]::ShowWindow($hwnd, 5) | Out-Null
                        [WinHelper]::SetForegroundWindow($hwnd) | Out-Null
                        return $false
                    }
                    return $true
                }
                [WinHelper]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
            }
            Start-Sleep -Milliseconds 500
        }
    }

    # Now show guidance while installer is running
    Write-ActionBox -Lines @(
        "E-APO installer is running.",
        "",
        "  -> Device Selector: just CLOSE it (X button)",
        "  -> Upgrades: click Yes",
        "  -> Other dialogs: click OK",
        "",
        "Press Enter here when E-APO is done."
    )

    # Clean up background focus job
    Stop-Job $focusJob -ErrorAction SilentlyContinue
    Remove-Job $focusJob -Force -ErrorAction SilentlyContinue

    # Wait for installer to finish if it hasn't already
    if (-not $proc.HasExited) {
        Write-Wait -Message "Finishing E-APO installation..." -Until { $proc.HasExited } -TimeoutSeconds 60 | Out-Null
    }
    Start-Sleep -Seconds 3

    # Verify. /D= is a REQUEST, not a guarantee -- an existing install's recorded path
    # can win it -- so a missing default config folder is checked against E-APO's own
    # key before it is called a failure. "Installed, but somewhere this script cannot
    # drive" is a different problem with a different fix, and saying so is the whole
    # reason Get-EapoInstallPath exists.
    if (-not (Test-Path $eapoConfig)) {
        Write-Host "$($script:BoxMargin)WARNING: Equalizer APO verification failed." -ForegroundColor Yellow
        $nowRoot = Get-EapoInstallPath
        if ($nowRoot -and -not [string]::Equals($nowRoot, $eapoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "$($script:BoxMargin)It installed to $nowRoot, not $eapoRoot." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)ArtTune only drives the default location. Remove Equalizer APO from" -ForegroundColor DarkGray
            Write-Host "$($script:BoxMargin)Add/Remove Programs, then re-run [1] Install." -ForegroundColor DarkGray
        }
        return $false
    }

    Write-Host "$($script:BoxMargin)Equalizer APO installed." -ForegroundColor Green

    # Create desktop shortcuts
    $desktopPath = [Environment]::GetFolderPath('Desktop')

    # ArtTuneDB folder inside E-APO config
    $artTuneDBDir = Join-Path $eapoConfig "ArtTuneDB"
    $artTuneDBLibrary = Join-Path $artTuneDBDir "library"
    try {
        New-Item -Path $artTuneDBLibrary -ItemType Directory -Force | Out-Null
        # README.txt is NOT written here. Write-FolderReadme emits it from the [1]
        # Install path instead, which is the only path that also knows whether
        # config.txt ended up with one chain or two ($TwoChains).
        Set-Content -Path (Join-Path $artTuneDBDir "ArtIsWar.url") -Value "[InternetShortcut]`r`nURL=https://artiswar.io"
        Set-Content -Path (Join-Path $artTuneDBDir "ArtTuneDB.url") -Value "[InternetShortcut]`r`nURL=https://github.com/ArtIsWar/ArtTuneDB"
        # Download ArtTuneDB icon
        $iconPath = Join-Path $artTuneDBDir "ArtTuneDB.ico"
        try {
            Invoke-WebRequest -Uri "https://cdn.artiswar.io/ArtTuneDBLogo.ico" -OutFile $iconPath -UseBasicParsing
        } catch {
            $iconPath = $null
            Write-Host "$($script:BoxMargin)Warning: Could not download icon: $_" -ForegroundColor Yellow
        }
        # Set custom folder icon via desktop.ini
        if ($iconPath -and (Test-Path $iconPath)) {
            try {
                $iniPath = Join-Path $artTuneDBDir "desktop.ini"
                $iniContent = "[.ShellClassInfo]`r`nIconResource=ArtTuneDB.ico,0"
                Set-Content -Path $iniPath -Value $iniContent -Force
                (Get-Item $iniPath).Attributes = 'Hidden,System'
                $dirItem = Get-Item $artTuneDBDir
                $dirItem.Attributes = $dirItem.Attributes -bor [System.IO.FileAttributes]::System
            } catch {
                Write-Host "$($script:BoxMargin)Warning: Could not set folder icon: $_" -ForegroundColor Yellow
            }
        }
        Write-Host "$($script:BoxMargin)ArtTuneDB folder created." -ForegroundColor Green
    } catch {
        Write-Host "$($script:BoxMargin)Warning: Could not create ArtTuneDB folder: $_" -ForegroundColor Yellow
    }

    # ArtTuneDB desktop shortcut (points to ArtTuneDB folder)
    try {
        $shortcutPath = Join-Path $desktopPath "ArtTuneDB.lnk"
        $ws = New-Object -ComObject WScript.Shell
        $shortcut = $ws.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $artTuneDBDir
        $shortcutIcon = Join-Path $artTuneDBDir "ArtTuneDB.ico"
        if (Test-Path $shortcutIcon) {
            $shortcut.IconLocation = "$shortcutIcon,0"
        } else {
            $shortcut.IconLocation = "shell32.dll,3"
        }
        $shortcut.Description = "ArtTuneDB folder"
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
        Write-Host "$($script:BoxMargin)Desktop shortcut created: ArtTuneDB" -ForegroundColor Green
    } catch {
        Write-Host "$($script:BoxMargin)Warning: Could not create ArtTuneDB shortcut: $_" -ForegroundColor Yellow
    }

    # E-APO Configuration Editor shortcut inside ArtTuneDB folder
    $editorExe = Join-Path $env:ProgramFiles "EqualizerAPO\Editor.exe"
    if (Test-Path $editorExe) {
        try {
            $shortcutPath = Join-Path $artTuneDBDir "E-APO Configuration Editor.lnk"
            $ws = New-Object -ComObject WScript.Shell
            $shortcut = $ws.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $editorExe
            $shortcut.WorkingDirectory = Join-Path $env:ProgramFiles "EqualizerAPO"
            $shortcut.Description = "Equalizer APO Configuration Editor"
            $shortcut.Save()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
            Write-Host "$($script:BoxMargin)E-APO Configuration Editor shortcut created in ArtTuneDB folder." -ForegroundColor Green
        } catch {
            Write-Host "$($script:BoxMargin)Warning: Could not create editor shortcut: $_" -ForegroundColor Yellow
        }
    }

    return $true
}

function Install-HeSuVi {
    <#
    .SYNOPSIS
        Installs HeSuVi with retry support for the interactive 7z SFX installer.
    #>
    param([ValidateNotNullOrEmpty()][string]$InstallerPath)

    Write-Host "$($script:BoxMargin)Installing HeSuVi..." -ForegroundColor Cyan

    $hesuviDir = Join-Path $env:ProgramFiles "EqualizerAPO\config\HeSuVi"
    if (Test-Path $hesuviDir) {
        Write-Host "$($script:BoxMargin)HeSuVi already installed." -ForegroundColor Green
        return $true
    }

    # HeSuVi is a 7z SFX -- no silent flag works. Retry loop lets the user
    # re-launch the installer if they accidentally cancel the extraction dialog.
    while ($true) {
        # Clean up any partial directory from a previous cancelled extraction
        Remove-Item $hesuviDir -Recurse -Force -ErrorAction SilentlyContinue

        Unblock-File -LiteralPath $InstallerPath -ErrorAction SilentlyContinue

        $proc = Start-Process -FilePath $InstallerPath -PassThru -ErrorAction Stop
        Set-WindowForeground -Process $proc

        Write-ActionBox -Lines @(
            "HeSuVi needs manual confirmation:",
            "",
            "  -> A dialog will appear -- click Yes / OK",
            "  -> Let it finish extracting",
            "  -> Close HeSuVi and the browser window it opens",
            "",
            "Come back here when it's done."
        )

        if (-not $proc.HasExited) {
            Write-Wait -Message "Finishing HeSuVi extraction..." -Until { $proc.HasExited } -TimeoutSeconds 120 | Out-Null
        }
        Start-Sleep -Seconds 2

        # Check expected path, search alternates if needed
        if (-not (Test-Path $hesuviDir)) {
            $altPaths = @(
                "$env:ProgramFiles\HeSuVi",
                "$env:USERPROFILE\Desktop\HeSuVi",
                "$env:TEMP\HeSuVi"
            )
            $foundPath = $altPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($foundPath) {
                Write-Host "$($script:BoxMargin)Found HeSuVi at $foundPath, moving to correct location..." -ForegroundColor DarkGray
                New-Item -ItemType Directory -Path $hesuviDir -Force | Out-Null
                Copy-Item -Path "$foundPath\*" -Destination $hesuviDir -Recurse -Force
                Remove-Item $foundPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # If directory exists now, installation succeeded -- break out of retry loop
        if (Test-Path $hesuviDir) {
            break
        }

        # HeSuVi not found -- offer retry or skip
        Write-Host ""
        Write-Host "$($script:BoxMargin)HeSuVi was not installed." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)The installer may have been cancelled." -ForegroundColor Yellow
        Write-Host ""
        $retryMenuItems = @(
            @{ Text = '[r] Retry - run the HeSuVi installer again'; Color = 'White' }
            @{ Text = '[s] Skip  - continue without HeSuVi'; Color = 'DarkGray' }
        )
        $retryMargin = Write-CenteredBlock $retryMenuItems
        Write-Host ""

        while ($true) {
            Write-Host "$retryMargin" -NoNewline
            Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
            $retryChoice = Read-Host
            if ($retryChoice -eq 'r' -or $retryChoice -eq 'R') {
                Write-Host "$($script:BoxMargin)Retrying HeSuVi installation..." -ForegroundColor Cyan
                break
            }
            if ($retryChoice -eq 's' -or $retryChoice -eq 'S') {
                Write-Host "$($script:BoxMargin)Skipping HeSuVi. You can install it manually later." -ForegroundColor Yellow
                return $false
            }
            Write-Host "$($script:BoxMargin)Invalid choice. Enter r to retry or s to skip." -ForegroundColor Red
        }
    }

    # Wipe EQ folder
    $eqPath = Join-Path $hesuviDir "eq"
    if (Test-Path $eqPath) {
        Remove-Item "$eqPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Verify
    $hesuviTxt = Join-Path $hesuviDir "hesuvi.txt"
    $convTxt = Join-Path $hesuviDir "conv.txt"
    if ((Test-Path $hesuviTxt) -and (Test-Path $convTxt)) {
        Write-Host "$($script:BoxMargin)HeSuVi installed (hesuvi.txt + conv.txt verified)." -ForegroundColor Green
    } elseif (Test-Path $hesuviDir) {
        Write-Host "$($script:BoxMargin)HeSuVi installed (config files will be generated on first GUI launch)." -ForegroundColor Green
    } else {
        Write-Host "$($script:BoxMargin)WARNING: HeSuVi verification incomplete." -ForegroundColor Yellow
    }
    return $true
}

function Get-HrirFile {
    <#
    .SYNOPSIS
        Downloads a single HRIR WAV file with progress display and validation.
    #>
    param(
        [string]$Url,
        [string]$Label,
        [string]$Destination
    )

    $tempFile = Join-Path $script:TempPath "hrir_$(Split-Path $Destination -Leaf)"

    $job = Start-Job -ScriptBlock {
        param($u, $o)
        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing -ErrorAction Stop
    } -ArgumentList $Url, $tempFile

    $outRef = $tempFile
    Write-Wait -Message "Downloading $Label..." -Until { $job.State -ne 'Running' } -TimeoutSeconds 120 -Progress {
        $pf = Get-Item $outRef -ErrorAction SilentlyContinue
        if ($pf) { Format-ByteSize -Bytes $pf.Length -Bracket }
    } | Out-Null

    if ($job.State -eq 'Failed') {
        $err = Receive-Job $job -ErrorAction SilentlyContinue 2>&1
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "$($script:BoxMargin)WARNING: Failed to download ${Label}: $err" -ForegroundColor Yellow
        return $null
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $tempFile)) {
        Write-Host "$($script:BoxMargin)WARNING: $Label download completed but file not found." -ForegroundColor Yellow
        return $null
    }
    $fileSize = (Get-Item $tempFile).Length
    if ($fileSize -eq 0) {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Write-Host "$($script:BoxMargin)WARNING: $Label download completed but file is empty." -ForegroundColor Yellow
        return $null
    }

    Copy-Item -Path $tempFile -Destination $Destination -Force
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    return $fileSize
}

function Install-ArtTuneHRIR {
    <#
    .SYNOPSIS
        Downloads the ArtTune HRIR files (EAC_Default and EAC_Refined, 48 kHz and
        44.1 kHz) into the HeSuVi hrir directory. These are NOT bundled in the
        library release, so they are fetched from the CDN.
    #>

    $hrirDir   = Join-Path $env:ProgramFiles "EqualizerAPO\config\HeSuVi\hrir"
    $hrir44Dir = Join-Path $hrirDir "44"

    $targets = @(
        @{ Name = 'EAC_Default'; Rate = '48 kHz';   Url = 'https://cdn.artiswar.io/HeSuVi/hrir/EAC_Default.wav';    Dest = (Join-Path $hrirDir   'EAC_Default.wav') }
        @{ Name = 'EAC_Default'; Rate = '44.1 kHz'; Url = 'https://cdn.artiswar.io/HeSuVi/hrir/44/EAC_Default.wav'; Dest = (Join-Path $hrir44Dir 'EAC_Default.wav') }
        @{ Name = 'EAC_Refined'; Rate = '48 kHz';   Url = 'https://cdn.artiswar.io/HeSuVi/hrir/EAC_Refined.wav';    Dest = (Join-Path $hrirDir   'EAC_Refined.wav') }
        @{ Name = 'EAC_Refined'; Rate = '44.1 kHz'; Url = 'https://cdn.artiswar.io/HeSuVi/hrir/44/EAC_Refined.wav'; Dest = (Join-Path $hrir44Dir 'EAC_Refined.wav') }
    )

    if (-not ($targets | Where-Object { -not (Test-Path $_.Dest) })) {
        Write-Host "$($script:BoxMargin)ArtTune HRIR already installed." -ForegroundColor Green
        return $true
    }

    Write-Host "$($script:BoxMargin)Installing ArtTune HRIR..." -ForegroundColor Cyan

    if (-not (Test-Path $hrirDir))   { New-Item -ItemType Directory -Path $hrirDir   -Force | Out-Null }
    if (-not (Test-Path $hrir44Dir)) { New-Item -ItemType Directory -Path $hrir44Dir -Force | Out-Null }

    $ok = $true
    foreach ($t in $targets) {
        if (Test-Path $t.Dest) { continue }
        $size = Get-HrirFile -Url $t.Url -Label "$($t.Name) ($($t.Rate))" -Destination $t.Dest
        if (-not $size) { $ok = $false }
    }

    if ($ok) {
        Write-Host "$($script:BoxMargin)ArtTune HRIR installed (EAC_Default + EAC_Refined, 48 kHz + 44.1 kHz)." -ForegroundColor Green
    } else {
        Write-Host "$($script:BoxMargin)WARNING: Some ArtTune HRIR files could not be downloaded." -ForegroundColor Yellow
    }
    return $ok
}

function Resolve-LibraryPayloadRoot {
    <#
    .SYNOPSIS
        Given an extracted release staging dir, returns the folder that DIRECTLY
        holds the flattened library payload (game folders + vst\ / jsfx\), whether
        the zip put them at root, wrapped them in library\, or wrapped everything
        in a single repo-root folder. Prevents a doubled library\library\ layout.
    #>
    param([string]$StagingDir)

    $looksLikeLibrary = {
        param($dir)
        if (-not $dir -or -not (Test-Path $dir)) { return $false }
        if (Test-Path (Join-Path $dir 'vst'))  { return $true }
        if (Test-Path (Join-Path $dir 'jsfx')) { return $true }
        foreach ($g in @('BF6', 'BO6', 'BO7', 'PS5-BO6', 'STD')) {
            if (Test-Path (Join-Path $dir $g)) { return $true }
        }
        return $false
    }

    # 1) payload at the staging root
    if (& $looksLikeLibrary $StagingDir) { return $StagingDir }
    # 2) wrapped in a top-level library\
    $lib = Join-Path $StagingDir 'library'
    if (& $looksLikeLibrary $lib) { return $lib }
    # 3) single wrapper subdir (repo-root style): that dir, or its library\
    $subs = @(Get-ChildItem -Path $StagingDir -Directory -ErrorAction SilentlyContinue)
    if ($subs.Count -eq 1) {
        $w = $subs[0].FullName
        if (& $looksLikeLibrary $w) { return $w }
        $wlib = Join-Path $w 'library'
        if (& $looksLikeLibrary $wlib) { return $wlib }
    }
    # 4) any nested library\ that looks right
    $found = Get-ChildItem -Path $StagingDir -Recurse -Directory -Filter 'library' -ErrorAction SilentlyContinue |
        Where-Object { & $looksLikeLibrary $_.FullName } | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Get-ArtTuneLibraryState {
    <#
    .SYNOPSIS
        Classifies the on-disk ArtTuneDB library for the Setup decision. Stamp
        presence only -- no version comparison, no manifest.
          'Versioned'      - library\version.txt exists. Keep it; skip install.
          'OldUnversioned' - no version.txt but real library content (.txt config /
                             squig EQ files, e.g. a pre-overhaul S-prefix library).
                             Back up (dated), then fresh-install.
          'None'           - absent, empty, or no real content. Fresh install.
    .OUTPUTS
        pscustomobject @{ State; Version }
    #>
    $libRoot     = Join-Path $script:ArtTuneDBRoot "library"
    $versionFile = Join-Path $libRoot "version.txt"
    if (Test-Path -LiteralPath $versionFile) {
        $ver = ''
        try { $ver = ("$(Get-Content -LiteralPath $versionFile -TotalCount 1 -ErrorAction Stop)").Trim() } catch { $ver = '' }
        return [pscustomobject]@{ State = 'Versioned'; Version = $ver }
    }
    if (Test-Path -LiteralPath $libRoot) {
        $realContent = @(Get-ChildItem -LiteralPath $libRoot -Recurse -File -Filter '*.txt' -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($realContent.Count -gt 0) { return [pscustomobject]@{ State = 'OldUnversioned'; Version = '' } }
    }
    return [pscustomobject]@{ State = 'None'; Version = '' }
}

function Install-ArtTuneLibrary {
    <#
    .SYNOPSIS
        Fetches the latest ArtTuneDB library release (.zip asset) and lays it down in
        the canonical ArtTuneDB root, automating the old manual "drag the library
        folder into E-APO config" ritual. Any existing library is backed up to a dated
        folder (unless -SkipBackup), then wiped and replaced with the fresh release
        (backup-then-nuke; no state file). The library is load-bearing, so hard failures
        surface with a retry affordance (never silently pass).
    .PARAMETER SkipBackup
        Skip the dated backup of the existing library. Used by the Setup fresh-install
        path when there is no real library worth preserving.
    #>
    param([switch]$SkipBackup)

    $libRoot = Join-Path $script:ArtTuneDBRoot "library"

    :libRetry while ($true) {
        Write-Host "$($script:BoxMargin)Fetching ArtTuneDB library release..." -ForegroundColor Cyan

        # --- Resolve the release .zip asset name ------------------------------
        # Single source of truth: the CDN latest-version.txt (same file the update
        # -check reads). Derive the standard asset name ArtTuneDB-<version>.zip from
        # it; fall back to the hardcoded $script:LibraryReleaseAsset when the CDN
        # version is unreachable/empty (e.g. test mode with no version file on R2).
        $assetName   = $script:LibraryReleaseAsset
        $downloadUrl = $null
        try {
            $verUrl = "$($script:LibraryMirrorBase.TrimEnd('/'))/ArtTuneDB/latest-version.txt"
            $verResp = Invoke-WebRequest -Uri $verUrl -UseBasicParsing -ErrorAction Stop
            $cdnVersion = ((("$($verResp.Content)") -split "`r?`n")[0]).Trim()
            if ($cdnVersion -and $cdnVersion -notmatch '[\\/\s]') {
                $assetName = "ArtTuneDB-$cdnVersion.zip"
                Write-Host "$($script:BoxMargin)Library version (CDN): $cdnVersion" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "$($script:BoxMargin)CDN version lookup failed; using default asset name." -ForegroundColor DarkGray
        }

        # GitHub API (when enabled) supplies the direct download URL and its own asset
        # name; otherwise the CDN-derived $assetName drives the R2 mirror fetch below.
        if ($script:UseGitHubRelease) {
            try {
                $headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'ArtTuneDB-Installer' }
                $release = Invoke-RestMethod $script:LibraryReleaseApi -Headers $headers -ErrorAction Stop
                $asset = $release.assets | Where-Object { Test-OrdinalContains "$($_.name)" '.zip' } | Select-Object -First 1
                if ($asset) { $assetName = $asset.name; $downloadUrl = $asset.browser_download_url }
            } catch {
                Write-Host "$($script:BoxMargin)GitHub release lookup failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        if (-not (Test-Path $script:TempPath)) { New-Item -ItemType Directory -Path $script:TempPath -Force | Out-Null }
        $zipPath = Join-Path $script:TempPath "ArtTuneDB-library.zip"
        $downloaded = $false

        # Try the GitHub asset, then the R2 mirror. Get-UrlToFile shows a live byte
        # counter (this used to be silent for the whole transfer) and enforces a
        # timeout, which neither of these fetches had at all.
        if ($downloadUrl) {
            $downloaded = Get-UrlToFile -Url $downloadUrl -OutFile $zipPath -Label "Downloading library..." -TimeoutSeconds 300
        }
        if (-not $downloaded) {
            $mirrorName = if ($assetName) { $assetName } else { 'ArtTuneDB-library.zip' }
            $mirrorUrl  = "$($script:LibraryMirrorBase.TrimEnd('/'))/ArtTuneDB/$mirrorName"
            Write-Host "$($script:BoxMargin)Trying mirror..." -ForegroundColor DarkGray
            $downloaded = Get-UrlToFile -Url $mirrorUrl -OutFile $zipPath -Label "Downloading library..." -TimeoutSeconds 300
        }

        if ($downloaded) {
            # --- Extract to staging, then normalize the payload root ---
            $staging = Join-Path $script:TempPath "ArtTuneDB-library-extract"
            if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $staging -Force | Out-Null
            $srcRoot = $null
            try {
                Expand-Archive -LiteralPath $zipPath -DestinationPath $staging -Force
                $srcRoot = Resolve-LibraryPayloadRoot -StagingDir $staging
            } catch {
                Write-Host "$($script:BoxMargin)Could not extract the library zip: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            if ($srcRoot) {
                # Normalize to the full/long path form so Copy-Item has a valid source.
                $srcRoot = (Get-Item -LiteralPath $srcRoot).FullName

                # --- Back up any existing library (dated), then wipe and replace ---
                # -is [bool] rather than -eq $false: a returned path string compared
                # against $false would coerce and could never match, so the guard has to
                # test the type. $null (nothing to back up) is not a failure.
                $backupDest = $null
                $backupFailed = $false
                if (-not $SkipBackup -and (Test-Path $libRoot)) {
                    $backupDest = Backup-ArtTuneLibrary
                    if ($backupDest -is [bool] -and -not $backupDest) { $backupFailed = $true }
                }

                if (-not $backupFailed) {
                    New-Item -ItemType Directory -Path $libRoot -Force | Out-Null
                    # Nuke the existing library so only the fresh release remains.
                    Get-ChildItem -Path $libRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                    # Lay down the fresh release.
                    Copy-Item -Path (Join-Path $srcRoot '*') -Destination $libRoot -Recurse -Force
                    $fileCount = @(Get-ChildItem -LiteralPath $libRoot -Recurse -File -ErrorAction SilentlyContinue).Count

                    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

                    if ($backupDest) {
                        Write-Host "$($script:BoxMargin)Previous library backed up to: $backupDest" -ForegroundColor DarkGray
                    }
                    Write-Host "$($script:BoxMargin)ArtTuneDB library installed ($fileCount files)." -ForegroundColor Green
                    return $true
                }

                # Backup failed. Leave the existing library exactly as it is: the user's
                # squig.link EQs live inside the tree the nuke would clear, and there
                # would be nothing to restore them from. Fall through to the retry menu.
                Write-Host "$($script:BoxMargin)Backup failed; your existing library was left untouched." -ForegroundColor Yellow
            }
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        }

        # --- Failure: surface clearly and offer retry (library is load-bearing) ---
        Write-Host ""
        Write-Host "$($script:BoxMargin)ERROR: Could not install the ArtTuneDB library." -ForegroundColor Red
        Write-Host "$($script:BoxMargin)Get it manually from: https://github.com/ArtIsWar/ArtTuneDB/releases" -ForegroundColor Yellow
        Write-Host ""
        $null = Write-CenteredBlock @(
            @{ Text = '[r] Retry library download'; Color = 'Yellow' }
            @{ Text = '[d] Open Discord for help';  Color = 'White' }
            @{ Text = '[s] Skip - continue without the library'; Color = 'DarkGray' }
        )
        Write-Host ""
        Write-Host "$($script:BoxMargin)" -NoNewline
        Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
        $libChoice = Read-Host
        switch ($libChoice.ToLower()) {
            'r' { continue libRetry }
            'd' {
                Start-Process 'https://discord.gg/artiswar'
                Write-Host "$($script:BoxMargin)Opened in browser. Press [r] then Enter to retry, or [s] to skip." -ForegroundColor Green
                $again = Read-Host
                if ($again.ToLower() -eq 's') { return $false }
                continue libRetry
            }
            's' {
                Write-Host "$($script:BoxMargin)Skipping library. Tunes and bundled VST/JSFX will be missing." -ForegroundColor Yellow
                return $false
            }
            default { continue libRetry }
        }
    }
}

function Get-BundledLibraryPath {
    <#
    .SYNOPSIS
        Resolves the bundled ArtTuneDB library root shipped with this release.
        Prefers the library next to the installer ($PSScriptRoot\..\library),
        then falls back to the installed ArtTuneDB library folder.
    #>
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path (Split-Path $PSScriptRoot -Parent) "library")
    }
    $candidates += (Join-Path $env:ProgramFiles "EqualizerAPO\config\ArtTuneDB\library")
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Install-JsfxPlugins {
    <#
    .SYNOPSIS
        Copies the bundled ArtTuneKit JSFX plugins into the ReaPlugs JS directory.
        The release is self-contained; no download.
    #>

    $jsfxDir = Join-Path $env:ProgramFiles "VSTPlugins\ReaPlugs\JS\Effects\ArtTuneKit"
    $file1 = Join-Path $jsfxDir "atk_spatial_engine.jsfx"
    $file2 = Join-Path $jsfxDir "atk_stereo_spatial_enhancer.jsfx"

    # Skip if both already installed
    if ((Test-Path $file1) -and (Test-Path $file2)) {
        Write-Host "$($script:BoxMargin)JSFX plugins already installed." -ForegroundColor Green
        return $true
    }

    # Check ReaPlugs is installed
    $reaPlugsDir = Join-Path $env:ProgramFiles "VSTPlugins\ReaPlugs"
    if (-not (Test-Path $reaPlugsDir)) {
        Write-Host "$($script:BoxMargin)WARNING: ReaPlugs not found. Install ReaPlugs first." -ForegroundColor Yellow
        return $false
    }

    # Locate the bundled jsfx\ in the release
    $bundled = Get-BundledLibraryPath
    $srcDir = if ($bundled) { Join-Path $bundled "jsfx" } else { $null }
    if (-not $srcDir -or -not (Test-Path $srcDir)) {
        Write-Host "$($script:BoxMargin)WARNING: bundled jsfx\ not found in the release; skipping JSFX install." -ForegroundColor Yellow
        return $false
    }

    $srcFiles = @(Get-ChildItem -Path $srcDir -Filter '*.jsfx' -File -ErrorAction SilentlyContinue)
    if ($srcFiles.Count -eq 0) {
        Write-Host "$($script:BoxMargin)WARNING: no .jsfx files in the bundle." -ForegroundColor Yellow
        return $false
    }

    Write-Host "$($script:BoxMargin)Installing JSFX plugins..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $jsfxDir -Force | Out-Null

    foreach ($f in $srcFiles) {
        Copy-Item -Path $f.FullName -Destination (Join-Path $jsfxDir $f.Name) -Force
    }

    # Verify the two known plugins landed
    if ((Test-Path $file1) -and (Test-Path $file2)) {
        Write-Host "$($script:BoxMargin)JSFX plugins installed to $jsfxDir" -ForegroundColor Green
        return $true
    }

    Write-Host "$($script:BoxMargin)WARNING: JSFX plugin verification failed." -ForegroundColor Yellow
    return $false
}

function Install-VstPlugins {
    <#
    .SYNOPSIS
        Copies the bundled ArtTuneKit VST DLL(s) into VSTPlugins\ArtTuneKit
        (the absolute path the native-VST configs reference). No download.
    #>

    $vstDir = Join-Path $env:ProgramFiles "VSTPlugins\ArtTuneKit"

    # Locate the bundled vst\ in the release
    $bundled = Get-BundledLibraryPath
    $srcDir = if ($bundled) { Join-Path $bundled "vst" } else { $null }
    if (-not $srcDir -or -not (Test-Path $srcDir)) {
        Write-Host "$($script:BoxMargin)WARNING: bundled vst\ not found in the release; skipping VST install." -ForegroundColor Yellow
        return $false
    }

    $srcDlls = @(Get-ChildItem -Path $srcDir -Filter '*.dll' -File -ErrorAction SilentlyContinue)
    if ($srcDlls.Count -eq 0) {
        Write-Host "$($script:BoxMargin)WARNING: no VST DLLs in the bundle." -ForegroundColor Yellow
        return $false
    }

    # Skip the copy if every bundled DLL is already present
    $allPresent = $true
    foreach ($dll in $srcDlls) {
        if (-not (Test-Path (Join-Path $vstDir $dll.Name))) { $allPresent = $false; break }
    }

    if (-not $allPresent) {
        Write-Host "$($script:BoxMargin)Installing ArtTuneKit VST..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $vstDir -Force | Out-Null
        foreach ($dll in $srcDlls) {
            Copy-Item -Path $dll.FullName -Destination (Join-Path $vstDir $dll.Name) -Force
        }
    }

    if ($allPresent) {
        Write-Host "$($script:BoxMargin)ArtTuneKit VST already installed." -ForegroundColor Green
    } else {
        Write-Host "$($script:BoxMargin)ArtTuneKit VST installed to $vstDir" -ForegroundColor Green
    }
    return $true
}

function Write-InitialConfig {
    <#
    .SYNOPSIS
        Writes the starter config.txt to the E-APO config folder.
        Always overwrites to ensure correct line order.

        Each profile lives in its own flattened folder:
        ArtTuneDB\library\<GAME>\<VERSION>\ (pre/post, target, eq\Flat_EQ.txt).
        The starter is an 8ch chain the user re-points to switch games/versions,
        plus a device-scoped 16ch (no-HeSuVi) chain when both endpoints resolved.
    .PARAMETER RenderGuid8
        Resolved 8ch "Art Tune" render endpoint GUID. When supplied, an active
        Device: line scopes the 8ch includes to that endpoint.
    .PARAMETER RenderGuid16
        Resolved 16ch "Art Tune +" render endpoint GUID. When supplied, a commented
        Device: line is emitted for the (commented) 16ch profile.
    #>
    param(
        [string]$RenderGuid8,
        [string]$RenderGuid16
    )

    $configFile = Join-Path $env:ProgramFiles "EqualizerAPO\config\config.txt"
    $boostFile  = Join-Path $script:ArtTuneDBRoot "boost.txt"

    # ALWAYS back up before overwriting. Done here rather than at the call site so
    # no future caller can write config.txt without a backup being taken first.
    $null = Backup-EAPOConfigFile

    # ---- Output Boost ------------------------------------------------------
    # A single Preamp line in ArtTuneDB\boost.txt, included LAST on each chain so it
    # lands after all other processing and is a true output gain (mirrors the
    # ArtTuneKit app's active-config\boost.txt).
    #
    # SEEDED ONCE, NEVER OVERWRITTEN. config.txt is rewritten on every run; the user's
    # boost value must survive that, and this lane has no picker UI to restore it from.
    # It sits at the ArtTuneDB ROOT, outside library\, so Install-ArtTuneLibrary's
    # backup-then-nuke of library\ cannot take it with it.
    #
    # The Preamp line ships LIVE at 0 dB (a genuine no-op), and so does the config.txt
    # Include. 0 dB is already the off state, so there is nothing to uncomment in either
    # file: setting the dB here IS the whole gesture, and it takes effect on save.
    if (-not (Test-Path -LiteralPath $boostFile)) {
        try {
            New-Item -ItemType Directory -Path $script:ArtTuneDBRoot -Force | Out-Null
            $boostLines = @(
                "# ArtTuneDB Output Boost -- set your dB below and save. 0 dB = off."
                "# config.txt includes this last on every chain; E-APO reloads it live."
                "Preamp: 0 dB"
            )
            Set-Content -Path $boostFile -Value ($boostLines -join "`r`n") -Force
        } catch {
            Write-Host "$($script:BoxMargin)WARNING: Could not write boost.txt: $_" -ForegroundColor Yellow
        }
    }

    # Normalize a raw endpoint GUID to E-APO's lowercase-braced form (matches the
    # ArtTuneKit app's BuildDeviceLine). Returns $null for empty input.
    $normGuid = {
        param($g)
        if ([string]::IsNullOrWhiteSpace($g)) { return $null }
        $g = $g.Trim().ToLowerInvariant()
        if ($g -notmatch '^\{') { $g = '{' + $g + '}' }
        return $g
    }
    $g8  = & $normGuid $RenderGuid8
    $g16 = & $normGuid $RenderGuid16

    # Device: lines scope the includes to the resolved VB-CABLE endpoints. Every
    # Device line carries the full GUID (never a bare "Art Tune"), so the shorter
    # "Art Tune" name cannot substring-match the longer "Art Tune +".
    #
    # NOTHING IS COMMENTED OUT. The two chains are scoped to DIFFERENT endpoints, so
    # both stay live and E-APO applies whichever one matches the device in use --
    # the same shape the ArtTuneKit app writes (BuildFullConfigWithPlus emits both
    # the 8ch and 16ch Device lines and both sections, uncommented).
    $device8Line  = if ($g8)  { "Device: Art Tune VB-Audio Virtual Cable $g8" }   else { $null }
    $device16Line = if ($g16) { "Device: Art Tune + VB-Audio Virtual Cable $g16" } else { $null }

    # The 16ch section is emitted ONLY when BOTH GUIDs resolved. Device scoping is
    # what keeps the two live chains apart, so a 16ch section without a Device line --
    # or alongside an unscoped 8ch section -- would stack both chains onto the same
    # endpoint. Mirrors the app: BuildFullConfigWithPlus falls back to the 8ch-only
    # BuildFullConfig when the plus GUID is missing.
    $emit16 = [bool]($device8Line -and $device16Line)

    try {
        # DELIBERATELY TERSE. This file is read while editing it, so every line of
        # prose pushes the Include lines further apart and buries the placeholders
        # the user came here to fill in. Each label is one line, each section header
        # states its own trade-off, and blank lines separate the two chains instead
        # of a "#" between every element. The long-form explanation is not lost --
        # Write-FolderReadme puts it in ArtTuneDB\README.txt, which is the right
        # place to read at length. Keep new guidance THERE, not here.
        $lines = @()
        # Line 1 is load-bearing and must stay EXACTLY this string: Backup-EAPOConfigFile
        # compares the first line against it to decide whether the config it is about to
        # replace is ours or the user's own. Change it there and here together, or a
        # hand-written config stops being backed up.
        $lines += "# ArtTuneDB config.txt"
        $lines += "# Complete each ""ArtTuneDB\library\"" path below, e.g. ...\BO7\V4\BO7_V4_pre.txt"
        if ($emit16) {
            $lines += "# Both sections are live -- switch device in game, do not comment either out."
        }
        $lines += ""
        $lines += "# ---- 8ch profile (Art Tune) - uses HeSuVi ----"
        if ($device8Line) { $lines += $device8Line }
        $lines += "# PRE HESUVI"
        $lines += "Include: ArtTuneDB\library\"
        $lines += "# DO NOT REMOVE HESUVI - LOAD HESUVI PRESET FOR VERSION #"
        $lines += "Include: HeSuVi\hesuvi.txt"
        $lines += "# EQ -- swap for your squig.link EQ (target file is in your version folder)"
        $lines += "Include: ArtTuneDB\library\"
        $lines += "# POST HESUVI"
        $lines += "Include: ArtTuneDB\library\"
        $lines += "# OUTPUT BOOST -- set your dB in ArtTuneDB\boost.txt (0 dB = off)"
        $lines += "Include: ArtTuneDB\boost.txt"
        if ($emit16) {
            $lines += ""
            $lines += "# ---- 16ch profile (Art Tune +) - no HeSuVi, needs the bundled VST ----"
            $lines += "# ONLY use files with _16ch_ in the name (see ""Choose a 16ch Tune.txt"")."
            $lines += $device16Line
            $lines += "# 16ch TUNE"
            $lines += "Include: ArtTuneDB\library\"
            $lines += "# EQ -- swap for your squig.link EQ"
            $lines += "Include: ArtTuneDB\library\"
            $lines += "# OUTPUT BOOST"
            $lines += "Include: ArtTuneDB\boost.txt"
        }

        Set-Content -Path $configFile -Value ($lines -join "`r`n") -Force

        # The template is deliberately unset: setup does not choose a tune. Say so here
        # rather than reporting a bare success, so nobody discovers the placeholders by
        # wondering why nothing sounds different. The completion box repeats it, since
        # this scrolls well off screen by the time setup finishes.
        $script:ConfigIsPlaceholder = $true

        Write-Host ""
        Write-Host "$($script:BoxMargin)ACTION REQUIRED: setup did not choose a tune for you." -ForegroundColor Yellow
        # Split by shape rather than patching one sentence: with no 16ch endpoint there
        # is only ONE chain in the file, and "both chains are live" would be advice the
        # user cannot act on.
        if ($emit16) {
            Write-Host "$($script:BoxMargin)config.txt has five placeholder Include paths to complete:" -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)three on the 8ch chain, two on the 16ch chain." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Both chains are live and scoped by device -- switch between them by" -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)picking the output device in game, not by editing config.txt." -ForegroundColor Yellow
        } else {
            Write-Host "$($script:BoxMargin)config.txt has three placeholder Include paths to complete," -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)all on the 8ch chain." -ForegroundColor Yellow
        }
        Write-Host "$($script:BoxMargin)Pick your game and version from:" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)$(Join-Path $script:ArtTuneDBRoot 'library')" -ForegroundColor Cyan
        Write-Host "$($script:BoxMargin)The ArtTuneDB desktop shortcut opens that folder." -ForegroundColor DarkGray
        Write-Host ""
        return $true
    } catch {
        Write-Host "$($script:BoxMargin)WARNING: Could not write config.txt: $_" -ForegroundColor Yellow
        return $false
    }
}

function Write-FolderReadme {
    <#
    .SYNOPSIS
        Writes the ArtTuneDB folder's README.txt quick-reference card.
    .DESCRIPTION
        Called from the [1] Install path, NOT from Install-Eapo where this used to live.
        Only the caller knows whether config.txt ended up with one chain or two, and the
        card must never describe a chain the config does not contain -- see $TwoChains.

        Overwritten unconditionally on every run. The file holds no user content, and
        replacing a stale card is the whole point.

        Failure is non-fatal and only warns, matching the behaviour at the old site.
    .PARAMETER TwoChains
        Whether config.txt carries both device-scoped chains. Must be passed the same
        signal Write-InitialConfig uses for $emit16, so the card can never describe a
        chain the config does not actually contain (PATH A resolves no endpoints and
        gets a single unscoped 8ch chain).
    #>
    param([bool]$TwoChains)

    # Literal here-strings: the card interpolates nothing, and $ appears in no line.
    $card = @'
ArtTuneDB
=========

ArtIsWar.url                    - artiswar.io
ArtTuneDB.url                   - ArtTuneDB project page
E-APO Configuration Editor.lnk  - Equalizer APO Configuration Editor
LEQ Control Panel.lnk           - Loudness EQ control panel
boost.txt                       - Optional output boost (one Preamp line)
library\                        - Game tunes, targets and EQ presets

FIRST: finish config.txt
  config.txt lives one folder up, in EqualizerAPO\config\.
  Setup does not pick a tune for you. Its Include lines stop at
  ArtTuneDB\library\ and you fill in the rest.
  Browse library\, pick your game and version, then complete each line.
  Example:  Include: ArtTuneDB\library\BO7\V4\BO7_V4_pre.txt

library\ is managed by setup
  Setup installs it and keeps it current. To refresh it, re-run setup
  and choose [3] Redownload Library.
  Do NOT put your own files in library\. A refresh backs the folder up
  and then clears it, so anything you add by hand is moved out from
  under you. Keep personal EQs elsewhere and point config.txt at them.

boost.txt
  Seeded once at "Preamp: 0 dB" and never overwritten, so a value you
  set survives later runs. config.txt already includes it last on every
  chain, so set your dB there and save. Nothing to uncomment. 0 dB = off.
'@

    if ($TwoChains) {
        $card += @'


Two chains, both live
  config.txt carries both, each scoped to its own output device:
    Art Tune    - 8ch chain, uses HeSuVi
    Art Tune +  - 16ch chain, no HeSuVi, uses the bundled VST
  Switch by choosing the output device in game, not by editing
  config.txt. Do not comment either one out.
'@
    }

    $card += @'


Help:      https://discord.gg/artiswar
Uninstall: re-run setup and choose [4] Uninstall everything
'@

    try {
        Set-Content -Path (Join-Path $script:ArtTuneDBRoot "README.txt") -Value $card
    } catch {
        Write-Host "$($script:BoxMargin)Warning: Could not write README.txt: $_" -ForegroundColor Yellow
    }
}

# ============================================================================
# SECTION 6: VB-CABLE Endpoint Configuration (.reg based)
# ============================================================================
# Detect the VB-CABLE render/capture endpoints, then rename + set icons via a
# single .reg import and one Audiosrv restart. Plain registry writes only -- no
# COM, no ACL P/Invoke, no mutex. Endpoint formats are NOT set here: format
# selection, along with everything else downstream of the endpoints (Device
# Selector, 7.1 config, LEQ, default device), stays in the user's guided
# walkthrough.

# Public Windows registry facts (MMDevices roots + property keys).
$script:MMDEVICES_RENDER  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$script:MMDEVICES_CAPTURE = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$script:PKEY_FRIENDLY   = "{a45c254e-df1c-4efd-8020-67d146a850e0},2"   # PKEY_Device_FriendlyName
$script:PKEY_DESC       = "{b3f8fa53-0004-438e-9003-51a46e139bfc},6"   # DeviceInterface desc
$script:PKEY_FORMFACTOR = "{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0"   # EndpointFormFactor (1=Speakers, 2=LineLevel)
$script:PKEY_ICON       = "{259abffc-50a7-47ce-af08-68c9a7d73366},12"  # PKEY_DeviceIcon

function Restart-AudioServices {
    <#
    .SYNOPSIS
        Restarts Windows audio services using Restart-Service -Force, which handles
        the Audiosrv/AudioEndpointBuilder dependency graph atomically.
    #>
    Write-Host ""
    Write-Host "$($script:BoxMargin)Restarting audio services..." -ForegroundColor Cyan

    try {
        Restart-Service -Name 'Audiosrv' -Force -ErrorAction Stop
    } catch {
        Write-Host "$($script:BoxMargin)Warning: Restart-Service failed ($_), retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        Restart-Service -Name 'Audiosrv' -Force -ErrorAction Stop
    }

    $running = Write-Wait -Message "Waiting for Audiosrv" -Until {
        $svc = Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
        $svc -and $svc.Status -eq 'Running'
    } -TimeoutSeconds 15

    if ($running) {
        Write-Host "$($script:BoxMargin)Audio services restarted." -ForegroundColor Green
    } else {
        Write-Host "$($script:BoxMargin)Warning: Audio services may not have restarted properly." -ForegroundColor Yellow
    }
}

function Get-ArtTuneEndpoints {
    <#
    .SYNOPSIS
        Detects the VB-CABLE render/capture endpoints among ACTIVE devices.
    .DESCRIPTION
        Family-matches the DeviceInterface desc == 'VB-Audio Virtual Cable' (so a
        user's own Hi-Fi Cable stays invisible), then uses the EndpointFormFactor
        property as the 8ch (1) vs 16ch (2) discriminator. Never bare-Contains
        "Art Tune". A clean VB-CABLE v45 install ships all three endpoints Active.
    .OUTPUTS
        pscustomobject @{ Render8; Render16; Capture } of GUIDs (any may be $null).
    #>
    $render8 = $null; $render16 = $null; $capture = $null

    if (Test-Path $script:MMDEVICES_RENDER) {
        foreach ($key in Get-ChildItem -Path $script:MMDEVICES_RENDER -ErrorAction SilentlyContinue) {
            try {
                $state = (Get-ItemProperty -Path $key.PSPath -Name 'DeviceState' -ErrorAction SilentlyContinue).DeviceState
                if ($state -ne 1) { continue }   # active only
                $propsPath = Join-Path $key.PSPath 'Properties'
                if (-not (Test-Path $propsPath)) { continue }
                $props = Get-ItemProperty -Path $propsPath -ErrorAction SilentlyContinue
                if ($props.$script:PKEY_DESC -ne 'VB-Audio Virtual Cable') { continue }
                $ff = [int]($props.$script:PKEY_FORMFACTOR)
                if ($ff -eq 2) {
                    if (-not $render16) { $render16 = $key.PSChildName }
                } else {
                    if (-not $render8) { $render8 = $key.PSChildName }
                }
            } catch { continue }
        }
    }

    if (Test-Path $script:MMDEVICES_CAPTURE) {
        foreach ($key in Get-ChildItem -Path $script:MMDEVICES_CAPTURE -ErrorAction SilentlyContinue) {
            try {
                $state = (Get-ItemProperty -Path $key.PSPath -Name 'DeviceState' -ErrorAction SilentlyContinue).DeviceState
                if ($state -ne 1) { continue }
                $propsPath = Join-Path $key.PSPath 'Properties'
                if (-not (Test-Path $propsPath)) { continue }
                $props = Get-ItemProperty -Path $propsPath -ErrorAction SilentlyContinue
                if ($props.$script:PKEY_DESC -ne 'VB-Audio Virtual Cable') { continue }
                if (-not $capture) { $capture = $key.PSChildName }
            } catch { continue }
        }
    }

    return [pscustomobject]@{ Render8 = $render8; Render16 = $render16; Capture = $capture }
}

function Get-VoicemeeterEndpoints {
    <#
    .SYNOPSIS
        Detects the Voicemeeter Standard render/capture endpoints among ACTIVE devices.
    .DESCRIPTION
        Carried over from the v1.1 installer, which renamed Voicemeeter Input to
        "Normal Audio" and Voicemeeter Out B1 to "Virtual Mix" -- the names the
        game settings pages (COD_SETTINGS.md, BF6_SETTINGS.md) tell users to pick.

        Matched by FRIENDLY NAME, not by the interface description the VB-CABLE
        path keys on: the VAIO description string varies across Voicemeeter
        builds, while these endpoint names have been stable. The target names are
        in the match sets too, so a second run resolves the same GUIDs and
        rewrites the same values instead of finding nothing to do.

        Case is not a concern -- string -eq is ordinal (see the culture-invariant
        matching note in SECTION 2), so one entry covers both the 'Voicemeeter'
        and 'VoiceMeeter' spellings VB-Audio has shipped.

        Standard-only is the CALLER's gate (Test-VoicemeeterEdition.Standard).
        The sets here are Standard-shaped regardless: Banana/Potato add Aux
        endpoints on the same driver, and 'Voicemeeter Aux Output' does not
        contain 'Voicemeeter Output', so they cannot be caught by accident.
    .OUTPUTS
        pscustomobject @{ Render; Capture } of GUIDs (either may be $null).
    #>
    $render = $null; $capture = $null

    if (Test-Path $script:MMDEVICES_RENDER) {
        foreach ($key in Get-ChildItem -Path $script:MMDEVICES_RENDER -ErrorAction SilentlyContinue) {
            try {
                $state = (Get-ItemProperty -Path $key.PSPath -Name 'DeviceState' -ErrorAction SilentlyContinue).DeviceState
                if ($state -ne 1) { continue }   # active only
                $propsPath = Join-Path $key.PSPath 'Properties'
                if (-not (Test-Path $propsPath)) { continue }
                $props = Get-ItemProperty -Path $propsPath -ErrorAction SilentlyContinue
                $name = "$($props.$script:PKEY_FRIENDLY)"
                if ($name -eq 'Voicemeeter Input' -or $name -eq 'Normal Audio') {
                    if (-not $render) { $render = $key.PSChildName }
                }
            } catch { continue }
        }
    }

    if (Test-Path $script:MMDEVICES_CAPTURE) {
        foreach ($key in Get-ChildItem -Path $script:MMDEVICES_CAPTURE -ErrorAction SilentlyContinue) {
            try {
                $state = (Get-ItemProperty -Path $key.PSPath -Name 'DeviceState' -ErrorAction SilentlyContinue).DeviceState
                if ($state -ne 1) { continue }
                $propsPath = Join-Path $key.PSPath 'Properties'
                if (-not (Test-Path $propsPath)) { continue }
                $props = Get-ItemProperty -Path $propsPath -ErrorAction SilentlyContinue
                $name = "$($props.$script:PKEY_FRIENDLY)"
                if ($name -eq 'Voicemeeter Out B1' -or $name -eq 'Virtual Mix' -or
                    (Test-OrdinalContains $name 'Voicemeeter Output')) {
                    if (-not $capture) { $capture = $key.PSChildName }
                }
            } catch { continue }
        }
    }

    return [pscustomobject]@{ Render = $render; Capture = $capture }
}

function Set-ArtTuneEndpoints {
    <#
    .SYNOPSIS
        Detect + rename + icon the VB-CABLE render/capture endpoints via a
        single .reg import and one Audiosrv restart (stripped-down OG style).
    .PARAMETER IncludeVoicemeeter
        Also rename the Voicemeeter Standard endpoints (Normal Audio / Virtual
        Mix), in the SAME .reg and the SAME restart. Caller-gated: pass $true
        only for a Voicemeeter Standard install the user actually asked for.
    .OUTPUTS
        pscustomobject @{ Render8; Render16; Capture } of GUIDs (any may be $null).
    #>
    param([string]$IconBaseUrl, [string]$Margin = '', [bool]$IncludeVoicemeeter = $false)

    Write-Host "$($Margin)Detecting VB-CABLE endpoints..." -ForegroundColor Cyan
    $eps = Get-ArtTuneEndpoints
    $r8 = $eps.Render8; $r16 = $eps.Render16; $cap = $eps.Capture

    if (-not $r8 -and -not $r16 -and -not $cap) {
        Write-Host "$($Margin)No active VB-CABLE endpoints detected; skipping endpoint configuration." -ForegroundColor Yellow
        # Verified = $false: nothing was read back because nothing was found, and a cable
        # that produced no endpoints is the more serious of the two failures this reports.
        return [pscustomobject]@{ Render8 = $null; Render16 = $null; Capture = $null; Verified = $false }
    }
    if ($r8)  { Write-Host "$($Margin)  Render 8ch  : $r8"  -ForegroundColor Cyan }
    if ($r16) { Write-Host "$($Margin)  Render 16ch : $r16" -ForegroundColor Cyan }
    if ($cap) { Write-Host "$($Margin)  Capture     : $cap" -ForegroundColor Cyan }
    if (-not ($r8 -and $r16 -and $cap)) {
        Write-Host "$($Margin)  WARNING: expected three active endpoints (8ch + 16ch render + capture); some were not found." -ForegroundColor Yellow
    }
    # 16ch guard: a missing Art Tune + endpoint is an explained 8ch-only fallback,
    # not a silent result. The r16 blocks below are already null-gated (no null-ref).
    if ($r8 -and -not $r16) {
        Write-Host "$($Margin)  WARNING: the 16ch endpoint (Art Tune +) was not found." -ForegroundColor Yellow
        Write-Host "$($Margin)  Only the 8ch endpoint (Art Tune) will be configured." -ForegroundColor Yellow
        Write-Host "$($Margin)  Likely cause: VB-CABLE is not exposing a 16ch render endpoint on this machine." -ForegroundColor Yellow
    }

    # --- Voicemeeter Standard endpoints (old-guide names) ---
    # Resolved AFTER the VB-CABLE early return above, deliberately: with no cable
    # endpoints the stack is broken and the user re-runs anyway, so a names-only
    # pass is not worth a second regedit import and a second Audiosrv restart.
    # Found endpoints ride along in the one .reg and the one restart below.
    $vmRender = $null; $vmCapture = $null
    if ($IncludeVoicemeeter) {
        Write-Host "$($Margin)Detecting Voicemeeter Standard endpoints..." -ForegroundColor Cyan
        $vmEps = Get-VoicemeeterEndpoints
        $vmRender = $vmEps.Render; $vmCapture = $vmEps.Capture
        if ($vmRender)  { Write-Host "$($Margin)  VM render   : $vmRender"  -ForegroundColor Cyan }
        if ($vmCapture) { Write-Host "$($Margin)  VM capture  : $vmCapture" -ForegroundColor Cyan }
        if (-not $vmRender -and -not $vmCapture) {
            # Not a failure: Voicemeeter can be installed with its driver not yet
            # enumerated (pending reboot). Nothing to rename, nothing to verify.
            Write-Host "$($Margin)  No active Voicemeeter endpoints found; leaving Voicemeeter names alone." -ForegroundColor DarkGray
        }
    }

    # --- Download the three endpoint icons (non-fatal) ---
    $iconDir = 'C:\ProgramData\ArtTune\icons'
    try {
        if (-not (Test-Path -LiteralPath $iconDir)) { New-Item -ItemType Directory -Path $iconDir -Force | Out-Null }
    } catch {
        Write-Host "$($Margin)  Could not create icon directory (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    $iconBase = if ($IconBaseUrl) { $IconBaseUrl.TrimEnd('/') } else { '' }
    $getIcon = {
        param($FileName)
        if ([string]::IsNullOrWhiteSpace($iconBase)) { return $null }
        $dest = Join-Path $iconDir $FileName
        try {
            Invoke-WebRequest -Uri "$iconBase/$FileName" -OutFile $dest -UseBasicParsing -ErrorAction Stop
            if (Test-Path -LiteralPath $dest) { return $dest }
        } catch {
            Write-Host "$($Margin)  Icon download failed for $FileName (non-fatal)." -ForegroundColor Yellow
        }
        return $null
    }
    $r8Icon  = if ($r8)  { & $getIcon 'ArtTuneCable.ico' }         else { $null }
    $r16Icon = if ($r16) { & $getIcon 'ArtTunePlusCable.ico' }     else { $null }
    $capIcon = if ($cap) { & $getIcon 'ArtTuneUnifiedOutput.ico' } else { $null }

    # Icon PKEY value = "<abs path>,0" with backslashes doubled for REG_SZ.
    $r8IconReg  = if ($r8Icon)  { ($r8Icon  + ',0') -replace '\\', '\\' } else { $null }
    $r16IconReg = if ($r16Icon) { ($r16Icon + ',0') -replace '\\', '\\' } else { $null }
    $capIconReg = if ($capIcon) { ($capIcon + ',0') -replace '\\', '\\' } else { $null }

    # --- Build ONE .reg: names + icons ---
    $renderKey  = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    $captureKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture'
    $reg = "Windows Registry Editor Version 5.00`r`n"

    if ($r8) {
        $reg += "`r`n[$renderKey\$r8\Properties]`r`n"
        $reg += "`"$script:PKEY_FRIENDLY`"=`"Art Tune`"`r`n"
        if ($r8IconReg) { $reg += "`"$script:PKEY_ICON`"=`"$r8IconReg`"`r`n" }
    }
    if ($r16) {
        $reg += "`r`n[$renderKey\$r16\Properties]`r`n"
        $reg += "`"$script:PKEY_FRIENDLY`"=`"Art Tune +`"`r`n"
        if ($r16IconReg) { $reg += "`"$script:PKEY_ICON`"=`"$r16IconReg`"`r`n" }
    }
    if ($cap) {
        $reg += "`r`n[$captureKey\$cap\Properties]`r`n"
        $reg += "`"$script:PKEY_FRIENDLY`"=`"Art Tune Unified Output`"`r`n"
        if ($capIconReg) { $reg += "`"$script:PKEY_ICON`"=`"$capIconReg`"`r`n" }
    }
    # Names only for Voicemeeter: v1.1 shipped no icons for these, and there are
    # no .ico assets for them to fetch.
    if ($vmRender) {
        $reg += "`r`n[$renderKey\$vmRender\Properties]`r`n"
        $reg += "`"$script:PKEY_FRIENDLY`"=`"Normal Audio`"`r`n"
    }
    if ($vmCapture) {
        $reg += "`r`n[$captureKey\$vmCapture\Properties]`r`n"
        $reg += "`"$script:PKEY_FRIENDLY`"=`"Virtual Mix`"`r`n"
    }

    Write-Host "$($Margin)Applying endpoint names and icons..." -ForegroundColor Cyan
    if (-not (Test-Path $script:TempPath)) { New-Item -ItemType Directory -Path $script:TempPath -Force | Out-Null }
    $regFile = Join-Path $script:TempPath "arttune_endpoints.reg"
    $reg | Out-File -FilePath $regFile -Encoding ASCII -Force

    try {
        $proc = Start-Process -FilePath 'regedit.exe' -ArgumentList "/s `"$regFile`"" -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -ne 0) {
            Write-Host "$($Margin)  WARNING: registry import returned exit code $($proc.ExitCode) (non-fatal)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "$($Margin)  WARNING: registry import failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Remove-Item $regFile -Force -ErrorAction SilentlyContinue

    # One restart finalizes the renames and icons.
    Restart-AudioServices

    # --- Read-back verify the three names and the icons we actually wrote ---
    # Expected icon value is the SINGLE-backslash form: $r8IconReg and friends are
    # .reg source literals with backslashes doubled for REG_SZ, and regedit stores
    # the unescaped path. Comparing against the doubled literal would never match.
    Start-Sleep -Milliseconds 200
    $expected = @()
    if ($r8)  { $expected += @{ Type = 'Render';  GUID = $r8;  Name = 'Art Tune';                Icon = $(if ($r8Icon)  { "$r8Icon,0" }  else { $null }) } }
    if ($r16) { $expected += @{ Type = 'Render';  GUID = $r16; Name = 'Art Tune +';              Icon = $(if ($r16Icon) { "$r16Icon,0" } else { $null }) } }
    if ($cap) { $expected += @{ Type = 'Capture'; GUID = $cap; Name = 'Art Tune Unified Output'; Icon = $(if ($capIcon) { "$capIcon,0" } else { $null }) } }
    # Icon-completeness is reported against the CABLE endpoints only -- the
    # Voicemeeter entries below carry no icon by design and would otherwise make
    # every run read as "icons where available".
    $cableCount = $expected.Count
    if ($vmRender)  { $expected += @{ Type = 'Render';  GUID = $vmRender;  Name = 'Normal Audio'; Icon = $null } }
    if ($vmCapture) { $expected += @{ Type = 'Capture'; GUID = $vmCapture; Name = 'Virtual Mix';  Icon = $null } }
    $allOk = $true
    $iconsAttempted = 0
    foreach ($e in $expected) {
        $propsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$($e.Type)\$($e.GUID)\Properties"
        try {
            $actual = (Get-ItemProperty -LiteralPath $propsPath -Name $script:PKEY_FRIENDLY -ErrorAction Stop).$script:PKEY_FRIENDLY
            if ($actual -ne $e.Name) { $allOk = $false }
        } catch { $allOk = $false }

        # Icons are best effort at DOWNLOAD time: an endpoint whose .ico never
        # arrived has no icon to verify and must not fail the check. One that WAS
        # written and does not read back means the .reg import silently dropped it
        # -- a real failure, treated exactly like a name mismatch.
        if ($e.Icon) {
            $iconsAttempted++
            try {
                $actualIcon = (Get-ItemProperty -LiteralPath $propsPath -Name $script:PKEY_ICON -ErrorAction Stop).$script:PKEY_ICON
                if ("$actualIcon" -ne $e.Icon) { $allOk = $false }
            } catch { $allOk = $false }
        }
    }

    if ($allOk) {
        if ($iconsAttempted -eq 0) {
            Write-Host "$($Margin)  Endpoints renamed and verified (names); no icons applied." -ForegroundColor Green
        } elseif ($iconsAttempted -eq $cableCount) {
            Write-Host "$($Margin)  Endpoints renamed and verified (names + icons)." -ForegroundColor Green
        } else {
            Write-Host "$($Margin)  Endpoints renamed and verified (names + icons where available)." -ForegroundColor Green
        }
    } else {
        Write-Host "$($Margin)  WARNING: endpoint name or icon verification incomplete (non-fatal)." -ForegroundColor Yellow
    }

    return [pscustomobject]@{ Render8 = $r8; Render16 = $r16; Capture = $cap; Verified = $allOk }
}

# ============================================================================
# SECTION 7: LEQ Control Panel Placement
# ============================================================================

function Install-SoundControl {
    <#
    .SYNOPSIS
        Installs the LEQ Control Panel executable and creates an ArtTuneDB shortcut.
    #>
    param([ValidateNotNullOrEmpty()][string]$SourcePath)

    Write-Host "$($script:BoxMargin)Installing LEQ Control Panel..." -ForegroundColor Cyan

    $scFolder = Join-Path $env:LOCALAPPDATA "Programs\LEQControlPanel"
    $scExe = Join-Path $scFolder "LEQControlPanel.exe"

    # Stop LEQ Control Panel if it's running (locks the exe)
    $running = Get-Process -Name "LEQControlPanel" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "$($script:BoxMargin)Closing running LEQ Control Panel..." -ForegroundColor DarkGray
        Stop-Process -Name "LEQControlPanel" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    # Create directory
    if (-not (Test-Path $scFolder)) {
        New-Item -ItemType Directory -Path $scFolder -Force | Out-Null
    }

    # Copy exe
    Copy-Item -LiteralPath $SourcePath -Destination $scExe -Force

    # Create shortcut in ArtTuneDB root folder
    $artTuneDBRoot = Join-Path $env:ProgramFiles "EqualizerAPO\config\ArtTuneDB"
    if (Test-Path $artTuneDBRoot) {
        try {
            $lnkPath = Join-Path $artTuneDBRoot "LEQ Control Panel.lnk"
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($lnkPath)
            $shortcut.TargetPath = $scExe
            $shortcut.WorkingDirectory = $scFolder
            $shortcut.Description = "LEQ Control Panel"
            $shortcut.Save()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        } catch {
            Write-Host "$($script:BoxMargin)Warning: Could not create ArtTuneDB library shortcut: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "$($script:BoxMargin)LEQ Control Panel installed." -ForegroundColor Green
    return $true
}

# ============================================================================
# SECTION 8: Main Execution Flow
# ============================================================================

try {
    Write-Banner
    Test-AdminPrivilege
    Test-SystemCompatibility
    Test-PowerShellEdition

    # Audio warning
    $null = Write-CenteredBlock @(@{ Text = "$([char]0x26A0) WARNING"; Color = 'Red' })
    $null = Write-CenteredBlock @(
        @{ Text = 'This installer will temporarily kill audio on this PC.'; Color = 'Red' }
        @{ Text = 'Watch the video guide on your phone or a different device.'; Color = 'Red' }
        @{ Text = 'Close all apps and save your work before continuing.'; Color = 'Red' }
    )

    :mainMenu while ($true) {

    Write-Host ""
    $menuItems = @(
        @{ Text = 'What would you like to do?'; Color = 'Yellow' }
        @{ Text = ''; Color = 'White' }
        @{ Text = '[1] Install - set up the audio stack (start here)'; Color = 'White' }
        @{ Text = '    Keeps Voicemeeter / Wave Link and anything else you already run.'; Color = 'DarkGray' }
        @{ Text = '[2] Start Clean - only if [1] is broken: wipe, restart, then re-run [1]'; Color = 'White' }
        @{ Text = '[3] Redownload Library - refresh the tune library (backs up your current one)'; Color = 'White' }
        @{ Text = '[4] Uninstall everything'; Color = 'White' }
        @{ Text = '[t] Thank you - Credits & developer links'; Color = 'White' }
        @{ Text = '[b] ArtTuneKit - automated, auto-updating, no Voicemeeter'; Color = 'DarkGray' }
        @{ Text = '[Q] Quit'; Color = 'DarkGray' }
    )
    $menuMargin = Write-CenteredBlock $menuItems
    Write-Host ""

    while ($true) {
        Write-Host "$menuMargin" -NoNewline
        Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        if ($selection -eq 't' -or $selection -eq 'T') {
            $result = Show-ThankYou
            if ($result -eq 'quit') { break mainMenu }
            continue mainMenu
        }
        if ($selection -eq 'b' -or $selection -eq 'B') {
            Start-Process "https://artiswar.io/arttunekit"
            Write-Host "$($script:BoxMargin)Opened in browser." -ForegroundColor Green
            continue mainMenu
        }
        if ($selection -eq 'q' -or $selection -eq 'Q') { break mainMenu }
        $num = 0
        if ([int]::TryParse($selection, [ref]$num) -and $num -ge 1 -and $num -le 4) {
            $menuChoice = $num
            break
        }
        Write-Host "$($script:BoxMargin)Invalid choice. Enter 1, 2, 3, 4, t, b, or q." -ForegroundColor Red
    }

    if ($menuChoice -eq 2) {
        # ===============================================================
        # START CLEAN: back up, remove everything, reboot, re-run Install
        # ===============================================================
        # Invoke-FreshStart reboots (or exits) once anything is removed, so it
        # only returns here when there was nothing to remove -- in which case the
        # PC is already clean and [1] Install is the next step. Voicemeeter is
        # deliberately NOT part of the wipe.
        $null = Invoke-FreshStart
        continue mainMenu

    } elseif ($menuChoice -eq 3) {
        # ===============================================================
        # REDOWNLOAD LIBRARY: back up current library, fresh configs only
        # ===============================================================
        Write-Host ""
        Write-Host "$($script:BoxMargin)This backs up your current ArtTuneDB library -- including any" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)squig.link EQs you added -- to a dated folder, then downloads a" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)fresh library. You will need to recopy or remake those EQs." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)Backup location: Documents\Art Tune Backups\library-<date>" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "$($script:BoxMargin)Continue? [Y/n]: " -ForegroundColor Yellow -NoNewline
        $libGo = Read-Host
        if ($libGo -eq 'n' -or $libGo -eq 'N') { continue mainMenu }

        if (-not (Test-Path $script:TempPath)) {
            New-Item -ItemType Directory -Path $script:TempPath -Force | Out-Null
        }
        # Library configs only -- backup + wipe + fresh download happen inside
        # Install-ArtTuneLibrary. VST / JSFX / HRIR are NOT re-moved here.
        $null = Install-ArtTuneLibrary
        Remove-Item $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Host "$($script:BoxMargin)Your previous library is in Documents\Art Tune Backups\ -- open the" -ForegroundColor DarkGray
        Write-Host "$($script:BoxMargin)ArtTuneDB desktop shortcut to recover old squig.link combos." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "$($script:BoxMargin)Done. Press any key to return to the menu." -ForegroundColor Green
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        continue mainMenu

    } elseif ($menuChoice -eq 4) {
        # ===============================================================
        # UNINSTALL EVERYTHING (no forced reboot; no reinstall)
        # ===============================================================
        # Voicemeeter is not removed unless asked. Name the edition so the choice
        # is answerable: only Standard is ever installed by this script, so Banana
        # or Potato means the user installed it themselves (and it is a paid,
        # licensed product) -- default to keeping those.
        $vm = Test-VoicemeeterEdition
        $wantVm = $false
        if ($vm.Present) {
            Write-Host ""
            if ($vm.PaidPresent) {
                # Stated, not asked. Uninstall-ExistingVoicemeeter refuses paid
                # editions outright (it returns 'Skipped'), so a remove prompt here
                # could only ever be a fake choice.
                Write-Host "$($script:BoxMargin)$($vm.Name) detected -- a licensed edition ArtTune did not" -ForegroundColor Yellow
                Write-Host "$($script:BoxMargin)install. Leaving it untouched." -ForegroundColor Yellow
            } else {
                Write-Host "$($script:BoxMargin)$($vm.Name) detected (installed by ArtTune)." -ForegroundColor Yellow
                Write-Host "$($script:BoxMargin)Remove it? [Y/n]: " -ForegroundColor Yellow -NoNewline
                $ans = Read-Host
                $wantVm = ($ans -ne 'n' -and $ans -ne 'N')
            }
        }

        # Desktop icons go first, before the wipe rather than after it. Every
        # removal below can fail hard on a locked driver or a dead audio service,
        # and the script-level catch would then skip anything that came after --
        # which is exactly how an ArtTuneDB icon pointing at a deleted folder
        # survived an uninstall. Nothing in the wipe needs these shortcuts.
        $lnkResult = Remove-ArtTuneDesktopShortcuts

        $result = Invoke-FreshStart -PromptRestart $false -IncludeVoicemeeter:$wantVm
        $removed = @($result.Removed)
        $kept    = @($result.Skipped)
        if ($vm.Present -and -not $wantVm) { $kept += $vm.Name }

        # Optional LEQ Control Panel removal
        Write-Host ""
        Write-Host "$($script:BoxMargin)Also remove LEQ Control Panel? [Y/n]: " -ForegroundColor Yellow -NoNewline
        $removeScp = Read-Host
        if ($removeScp -ne 'n' -and $removeScp -ne 'N') {
            if (Uninstall-SoundControl) { $removed += "LEQ Control Panel" }
        }

        Write-UninstallCompletion -RemovedComponents $removed -KeptComponents $kept `
            -RemovedShortcuts $lnkResult.Removed -FailedShortcuts $lnkResult.Failed

        # Prompt restart if drivers were removed
        if ($removed | Where-Object { $_ -ne 'LEQ Control Panel' }) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)A restart is recommended to fully clear removed drivers." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "$($script:BoxMargin)Restart now? [Y/n]: " -ForegroundColor Yellow -NoNewline
            $restart = Read-Host
            if ($restart -ne 'n' -and $restart -ne 'N') {
                Restart-Computer -Force
            }
        }
        continue mainMenu

    } else {
        # ===============================================================
        # INSTALL: set up the stack, keeping what is already present
        # ===============================================================
        # The retired Hi-Fi Cable is removed rather than warned about. It is the
        # OLD Art Tune cable, so leaving it behind means two similar-looking
        # devices in the sound panel and constant user confusion. This is a
        # cosmetic cleanup, NOT a prerequisite: VB-CABLE and Hi-Fi Cable have
        # distinct interface descriptions and Get-ArtTuneEndpoints ignores Hi-Fi
        # entirely, so nothing here needs a reboot to proceed.
        $lingeringHifi = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-OrdinalContains "$($_.Name)" 'Hi-Fi') -or
                (Test-OrdinalContains "$($_.Name)" 'HiFi')
            }
        $hifiLeftBehind = $false
        if ($lingeringHifi) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)Hi-Fi Cable (the old Art Tune cable) is still installed." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Removing it so it cannot be confused with the new endpoints." -ForegroundColor DarkGray
            if ((Uninstall-ExistingHiFiCable) -ne 'Removed') { $hifiLeftBehind = $true }
        }

        # Voicemeeter installs by default -- most users need a mixer -- but never
        # on top of one the user actually relies on. Detection alone cannot decide
        # that: Wave Link ships with Elgato capture hardware and is often present
        # but unused (sometimes without its audio driver at all), and a stale
        # Voicemeeter folder proves nothing either. So detection picks WHAT TO ASK
        # ABOUT, and the user confirms per product.
        $mixers = @(Get-InstalledMixers)
        $wantVoicemeeter = $true
        $usesExisting = $false

        if ($mixers.Count -gt 0) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)Found an audio mixer already installed on this PC." -ForegroundColor Yellow
            foreach ($mx in $mixers) {
                Write-Host "$($script:BoxMargin)Do you use $($mx.Name) as your mixer? [Y/n]: " -ForegroundColor Yellow -NoNewline
                $mxAns = Read-Host
                if ($mxAns -ne 'n' -and $mxAns -ne 'N') { $usesExisting = $true }
            }

            if ($usesExisting) {
                $wantVoicemeeter = $false
                Write-Host "$($script:BoxMargin)Keeping your mixer -- Voicemeeter will not be installed." -ForegroundColor DarkGray
            } else {
                # Nothing here is in use, so Voicemeeter Standard goes in as normal
                # -- except on top of a paid edition. All editions share one folder,
                # one uninstall entry and one audio driver, so Standard can strip the
                # extra virtual inputs Potato/Banana paid for and take over their
                # uninstaller. That is still the user's call, but it has to be made
                # deliberately: this prompt defaults to NO, unlike the [Y/n] above.
                $blocker = $mixers | Where-Object { $_.Blocking } | Select-Object -First 1
                if ($blocker) {
                    Write-Host ""
                    Write-Host "$($script:BoxMargin)Heads up: $($blocker.Name) is a paid edition, and every Voicemeeter" -ForegroundColor Yellow
                    Write-Host "$($script:BoxMargin)edition shares one folder, one uninstall entry and one audio driver." -ForegroundColor Yellow
                    Write-Host "$($script:BoxMargin)Installing Voicemeeter Standard over it can remove the extra virtual" -ForegroundColor Yellow
                    Write-Host "$($script:BoxMargin)inputs you paid for and take over its uninstaller." -ForegroundColor Yellow
                    Write-Host "$($script:BoxMargin)Safer: remove it from Add/Remove Programs first, then run this again." -ForegroundColor DarkGray
                    Write-Host ""
                    Write-Host "$($script:BoxMargin)Install Voicemeeter Standard anyway? [y/N]: " -ForegroundColor Yellow -NoNewline
                    $ovrAns = Read-Host
                    if ($ovrAns -eq 'y' -or $ovrAns -eq 'Y') {
                        Write-Host "$($script:BoxMargin)Installing Voicemeeter Standard alongside $($blocker.Name)." -ForegroundColor DarkGray
                    } else {
                        $wantVoicemeeter = $false
                        Write-Host "$($script:BoxMargin)Leaving $($blocker.Name) alone -- Voicemeeter will not be installed." -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "$($script:BoxMargin)Installing Voicemeeter as part of the stack." -ForegroundColor DarkGray
                }
            }
        }

        Write-Host ""
        :dlRetryB while ($true) {
            try {
                $files = Get-Downloads -IncludeVirtualAudio -WantVoicemeeter $wantVoicemeeter
                break dlRetryB
            } catch {
                Write-Host ""
                Write-Host "$($script:BoxMargin)Download failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                :dlMenuB while ($true) {
                    $null = Write-CenteredBlock @(
                        @{ Text = '[r] Retry downloads'; Color = 'Yellow' }
                        @{ Text = '[d] Open Discord for help'; Color = 'White' }
                        @{ Text = '[m] Back to main menu'; Color = 'DarkGray' }
                    )
                    Write-Host ""
                    Write-Host "$($script:BoxMargin)" -NoNewline
                    Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
                    $dlChoice = Read-Host
                    switch ($dlChoice.ToLower()) {
                        'r' { break dlMenuB }
                        'd' {
                            Start-Process 'https://discord.gg/artiswar'
                            Write-Host "$($script:BoxMargin)Opened in browser." -ForegroundColor Green
                            Write-Host ""
                        }
                        'm' { continue mainMenu }
                        default { Write-Host "$($script:BoxMargin)Invalid choice." -ForegroundColor Red; Write-Host "" }
                    }
                }
            }
        }

        # Component results for the completion summary. Initialized to $true BEFORE each
        # guard, because a null $files.X means "already installed, nothing to fetch" --
        # a fatal download failure throws inside Get-Downloads and never reaches here, so
        # the skipped case is a genuine success. Only SoundControl can be null because it
        # FAILED, and that one is reported from $files below rather than from a capture.
        $okVBCable  = $true
        $okVoicemeeter = $true
        $okReaPlugs = $true
        $okEapo     = $true
        $okHeSuVi   = $true
        $okJsfx     = $true

        Write-Host ""
        Write-Host "$($script:BoxMargin)Installing [1/9]..." -ForegroundColor Yellow
        # VB-CABLE installs only when its endpoints do not already resolve
        # (Get-Downloads leaves $files.VBCable null in that case).
        if ($files.VBCable) { $okVBCable = Install-VBCable -ZipPath $files.VBCable }
        Write-Host "$($script:BoxMargin)Installing [2/9]..." -ForegroundColor Yellow
        if ($files.Voicemeeter) { $okVoicemeeter = Install-Voicemeeter -ZipPath $files.Voicemeeter }
        Write-Host "$($script:BoxMargin)Installing [3/9]..." -ForegroundColor Yellow
        if ($files.ReaPlugs) { $okReaPlugs = Install-ReaPlugs -InstallerPath $files.ReaPlugs }

        # Configure the VB-CABLE endpoints (detect/rename/format/icons). Ported
        # ArtTuneKit stack; restarts audio internally where needed. Returns the
        # resolved render/capture GUIDs for the device-scoped config.txt below.
        #
        # The v1.1 Voicemeeter names (Normal Audio / Virtual Mix) ride along, but
        # ONLY for a Voicemeeter Standard install we were asked for. Two gates,
        # both required:
        #   Standard, no paid edition -- Banana/Potato are the user's own install
        #     (Test-VoicemeeterEdition doubles as provenance) and every edition
        #     shares the one VAIO driver, so renaming its endpoints on a paid box
        #     renames devices the user set up themselves. Also covers the
        #     "install Standard anyway" override above, which leaves both present.
        #   $wantVoicemeeter -- false means the user kept Wave Link or a paid
        #     mixer. We do not install their mixer, so we do not rename it either.
        $vmEdition = Test-VoicemeeterEdition
        $renameVoicemeeter = ($wantVoicemeeter -and $vmEdition.Standard -and -not $vmEdition.PaidPresent)
        Write-Host "$($script:BoxMargin)Installing [4/9]..." -ForegroundColor Yellow
        $script:ArtTuneEndpoints = Set-ArtTuneEndpoints -IconBaseUrl $script:AssetBase -Margin $script:BoxMargin -IncludeVoicemeeter $renameVoicemeeter

        Write-Host "$($script:BoxMargin)Installing [5/9]..." -ForegroundColor Yellow
        if ($files.EAPO) { $okEapo = Install-Eapo -InstallerPath $files.EAPO }
        # Version-aware library decision (stamp presence only; no compare, no manifest).
        $libState = Get-ArtTuneLibraryState
        if ($libState.State -eq 'Versioned') {
            $verLabel = if ($libState.Version) { " $($libState.Version)" } else { "" }
            Write-Host "$($script:BoxMargin)Existing ArtTuneDB library$verLabel detected - keeping it." -ForegroundColor Green
            Write-Host "$($script:BoxMargin)Use [3] Redownload Library to update (it backs up your custom EQs first)." -ForegroundColor DarkGray
        } elseif ($libState.State -eq 'OldUnversioned') {
            Write-Host "$($script:BoxMargin)An older ArtTuneDB library (no version stamp) was found." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Backing it up to Documents\Art Tune Backups\, then installing the new versioned library..." -ForegroundColor Yellow
            $null = Install-ArtTuneLibrary
            Write-Host "$($script:BoxMargin)Old squig.link EQs are recoverable from that backup via the ArtTuneDB desktop shortcut." -ForegroundColor DarkGray
        } else {
            $null = Install-ArtTuneLibrary -SkipBackup
        }
        Write-Host "$($script:BoxMargin)Installing [6/9]..." -ForegroundColor Yellow
        if ($files.HeSuVi) { $okHeSuVi = Install-HeSuVi -InstallerPath $files.HeSuVi }
        Write-Host "$($script:BoxMargin)Installing [7/9]..." -ForegroundColor Yellow
        $null = Install-ArtTuneHRIR
        $null = Write-InitialConfig -RenderGuid8 $script:ArtTuneEndpoints.Render8 -RenderGuid16 $script:ArtTuneEndpoints.Render16
        # After Write-InitialConfig, which is what creates the config.txt and boost.txt
        # the card describes and guarantees the ArtTuneDB folder exists. Unconditional
        # on this path, so the card is refreshed on every run. The -TwoChains signal is
        # Write-InitialConfig's own $emit16 condition.
        Write-FolderReadme -TwoChains ([bool]($script:ArtTuneEndpoints.Render8 -and $script:ArtTuneEndpoints.Render16))
        Write-Host "$($script:BoxMargin)Installing [8/9]..." -ForegroundColor Yellow
        $okJsfx = Install-JsfxPlugins
        $null = Install-VstPlugins
        Write-Host "$($script:BoxMargin)Installing [9/9]..." -ForegroundColor Yellow
        if ($files.SoundControl) {
            $null = Install-SoundControl -SourcePath $files.SoundControl
        } elseif ($files.SoundControlPresent) {
            Write-Host "$($script:BoxMargin)LEQ Control Panel already installed." -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "$($script:BoxMargin)LEQ Control Panel download failed." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)Press [d] to open the GitHub releases page, or any other key to continue." -ForegroundColor Yellow
            Write-Host ""
            $dlKey = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
            if ($dlKey -eq 'd' -or $dlKey -eq 'D') {
                Start-Process 'https://github.com/ArtIsWar/LEQControlPanel/releases'
                Write-Host "$($script:BoxMargin)Opened in browser." -ForegroundColor Green
            }
        }

        # Anonymous setup counter (success path only).
        Send-SetupPing -Mode 'voicemeeter'

        # The install itself never requires a reboot. If the old Hi-Fi Cable was
        # removed, a restart only clears it from the device list -- say so plainly
        # so nobody reads a leftover entry as a failed install.
        if ($lingeringHifi) {
            Write-Host ""
            if ($hifiLeftBehind) {
                Write-Host "$($script:BoxMargin)Note: Hi-Fi Cable could not be fully removed." -ForegroundColor Yellow
                Write-Host "$($script:BoxMargin)Your install is complete and working -- restart to clear it, or" -ForegroundColor DarkGray
                Write-Host "$($script:BoxMargin)remove 'VB-Audio Hi-Fi Cable' from Device Manager." -ForegroundColor DarkGray
            } else {
                Write-Host "$($script:BoxMargin)Note: the old Hi-Fi Cable was removed. Restart when convenient to" -ForegroundColor DarkGray
                Write-Host "$($script:BoxMargin)clear it from your sound device list. Nothing else is waiting on it." -ForegroundColor DarkGray
            }
        }

        # ExePresent, not Present: a leftover uninstall registry key with nothing on
        # disk is not a mixer, and must not render a green tick. ANDed with the
        # install result so a failed install is never reported as a success.
        $vmFinal = ((Test-VoicemeeterEdition).ExePresent -and $okVoicemeeter)
        $result = Write-Completion `
            -SoundControlInstalled ([bool]($files.SoundControl -or $files.SoundControlPresent)) `
            -VoicemeeterInstalled $vmFinal `
            -VBCableInstalled $okVBCable `
            -ReaPlugsInstalled $okReaPlugs `
            -EapoInstalled $okEapo `
            -HeSuViInstalled $okHeSuVi `
            -JsfxInstalled $okJsfx `
            -EndpointsVerified $script:ArtTuneEndpoints.Verified `
            -ConfigIsPlaceholder $script:ConfigIsPlaceholder

        # Cleanup
        Remove-Item $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue

        if ($result -eq 'mainMenu') { continue mainMenu }
        if ($result -eq 'quit') { break mainMenu }
    }

    # All paths complete -- exit the main menu loop
    break

    } # end :mainMenu

} catch {
    Write-Host ""
    Write-Host "$($script:BoxMargin)FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "$($script:BoxMargin)Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host ""
    Write-Host "$($script:BoxMargin)If this keeps happening, report it at:" -ForegroundColor White
    Write-Host "$($script:BoxMargin)https://discord.gg/artiswar" -ForegroundColor Cyan
    Write-Host ""
} finally {
    # Runs on the success path, the fatal path, and any future exit from the menu loop.
    # The success-path cleanup above stays: it clears temp per menu iteration, which this
    # alone would not do once the flow hits "continue mainMenu". Both are idempotent.
    Remove-Item $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
}


# SIG # Begin signature block
# MIIxdwYJKoZIhvcNAQcCoIIxaDCCMWQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDIw9TMndDoMt+X
# 1dB6EUZYg0oqgcTbfre8sDzQDdFKuKCCKokwggQyMIIDGqADAgECAgEBMA0GCSqG
# SIb3DQEBBQUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQIDBJHcmVhdGVyIE1hbmNo
# ZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoMEUNvbW9kbyBDQSBMaW1p
# dGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2VydmljZXMwHhcNMDQwMTAx
# MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjB7MQswCQYDVQQGEwJHQjEbMBkGA1UECAwS
# R3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHDAdTYWxmb3JkMRowGAYDVQQKDBFD
# b21vZG8gQ0EgTGltaXRlZDEhMB8GA1UEAwwYQUFBIENlcnRpZmljYXRlIFNlcnZp
# Y2VzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvkCd9G7h6naHHE1F
# RI6+RsiDBp3BKv4YH47kAvrzq11QihYxC5oG0MVwIs1JLVRjzLZuaEYLU+rLTCTA
# vHJO6vEVrvRUmhIKw3qyM2Di2olV8yJY897cz++DhqKMlE+faPKYkEaEJ8d2v+PM
# NSyLXgdkZYLASLCokflhn3YgUKiRx2a163hiA1bwihoT6jGjHqCZ/Tj29icyWG8H
# 9Wu4+xQrr7eqzNZjX3OM2gWZqDioyxd4NlGs6Z70eDqNzw/ZQuKYDKsvnw4B3u+f
# mUnxLd+sdE0bmLVHxeUp0fmQGMdinL6DxyZ7Poolx8DdneY1aBAgnY/Y3tLDhJwN
# XugvyQIDAQABo4HAMIG9MB0GA1UdDgQWBBSgEQojPpbxB+zirynvgqV/0DCktDAO
# BgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zB7BgNVHR8EdDByMDigNqA0
# hjJodHRwOi8vY3JsLmNvbW9kb2NhLmNvbS9BQUFDZXJ0aWZpY2F0ZVNlcnZpY2Vz
# LmNybDA2oDSgMoYwaHR0cDovL2NybC5jb21vZG8ubmV0L0FBQUNlcnRpZmljYXRl
# U2VydmljZXMuY3JsMA0GCSqGSIb3DQEBBQUAA4IBAQAIVvwC8Jvo/6T61nvGRIDO
# T8TF9gBYzKa2vBRJaAR26ObuXewCD2DWjVAYTyZOAePmsKXuv7x0VEG//fwSuMdP
# WvSJYAV/YLcFSvP28cK/xLl0hrYtfWvM0vNG3S/G4GrDwzQDLH2W3VrCDqcKmcEF
# i6sML/NcOs9sN1UJh95TQGxY7/y2q2VuBPYb3DzgWhXGntnxWUgwIWUDbOzpIXPs
# mwOh4DetoBUYj/q6As6nLKkQEyzU5QgmqyKXYPiQXnTUoppTvfKpaOCibsLXbLGj
# D56/62jnVvKu8uMrODoJgbVrhde+Le0/GreyY+L1YiyC1GoAQVDxOYOflek2lphu
# MIIFbzCCBFegAwIBAgIQSPyTtGBVlI02p8mKidaUFjANBgkqhkiG9w0BAQwFADB7
# MQswCQYDVQQGEwJHQjEbMBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYD
# VQQHDAdTYWxmb3JkMRowGAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEhMB8GA1UE
# AwwYQUFBIENlcnRpZmljYXRlIFNlcnZpY2VzMB4XDTIxMDUyNTAwMDAwMFoXDTI4
# MTIzMTIzNTk1OVowVjELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGlt
# aXRlZDEtMCsGA1UEAxMkU2VjdGlnbyBQdWJsaWMgQ29kZSBTaWduaW5nIFJvb3Qg
# UjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjeeUEiIEJHQu/xYj
# ApKKtq42haxH1CORKz7cfeIxoFFvrISR41KKteKW3tCHYySJiv/vEpM7fbu2ir29
# BX8nm2tl06UMabG8STma8W1uquSggyfamg0rUOlLW7O4ZDakfko9qXGrYbNzszwL
# DO/bM1flvjQ345cbXf0fEj2CA3bm+z9m0pQxafptszSswXp43JJQ8mTHqi0Eq8Nq
# 6uAvp6fcbtfo/9ohq0C/ue4NnsbZnpnvxt4fqQx2sycgoda6/YDnAdLv64IplXCN
# /7sVz/7RDzaiLk8ykHRGa0c1E3cFM09jLrgt4b9lpwRrGNhx+swI8m2JmRCxrds+
# LOSqGLDGBwF1Z95t6WNjHjZ/aYm+qkU+blpfj6Fby50whjDoA7NAxg0POM1nqFOI
# +rgwZfpvx+cdsYN0aT6sxGg7seZnM5q2COCABUhA7vaCZEao9XOwBpXybGWfv1Vb
# HJxXGsd4RnxwqpQbghesh+m2yQ6BHEDWFhcp/FycGCvqRfXvvdVnTyheBe6QTHrn
# xvTQ/PrNPjJGEyA2igTqt6oHRpwNkzoJZplYXCmjuQymMDg80EY2NXycuu7D1fkK
# dvp+BRtAypI16dV60bV/AK6pkKrFfwGcELEW/MxuGNxvYv6mUKe4e7idFT/+IAx1
# yCJaE5UZkADpGtXChvHjjuxf9OUCAwEAAaOCARIwggEOMB8GA1UdIwQYMBaAFKAR
# CiM+lvEH7OKvKe+CpX/QMKS0MB0GA1UdDgQWBBQy65Ka/zWWSC8oQEJwIDaRXBeF
# 5jAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUEDDAKBggr
# BgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEMGA1UdHwQ8MDow
# OKA2oDSGMmh0dHA6Ly9jcmwuY29tb2RvY2EuY29tL0FBQUNlcnRpZmljYXRlU2Vy
# dmljZXMuY3JsMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuY29tb2RvY2EuY29tMA0GCSqGSIb3DQEBDAUAA4IBAQASv6Hvi3SamES4aUa1
# qyQKDKSKZ7g6gb9Fin1SB6iNH04hhTmja14tIIa/ELiueTtTzbT72ES+BtlcY2fU
# QBaHRIZyKtYyFfUSg8L54V0RQGf2QidyxSPiAjgaTCDi2wH3zUZPJqJ8ZsBRNraJ
# AlTH/Fj7bADu/pimLpWhDFMpH2/YGaZPnvesCepdgsaLr4CnvYFIUoQx2jLsFeSm
# TD1sOXPUC4U5IOCFGmjhp0g4qdE2JXfBjRkWxYhMZn0vY86Y6GnfrDyoXZ3JHFuu
# 2PMvdM+4fvbXg50RlmKarkUT2n/cR/vfw1Kf5gZV6Z2M8jpiUbzsJA8p1FiAhORF
# e1rYMIIGHDCCBASgAwIBAgIQM9cIqJFAUxnipbvTObmtbjANBgkqhkiG9w0BAQwF
# ADBWMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYD
# VQQDEyRTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwHhcNMjEw
# MzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5WjBXMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMS4wLAYDVQQDEyVTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgRVYgUjM2MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKC
# AYEAu9H+HrdCW3j1kKeuLIPxjSHTMIaFe9/TzdkWS6yFxbsBz+KMKBFyBHYsgcWr
# EnpASsUQ6IEUORtfTwf2MDAwfzUl5cBzPUAJlOio+Os5C1XVtgyLHif43j4iwb/v
# Ze5z7mXdKN27H32bMn+3mVUXqrJJqDwQajrDIbKZqEPXO4KoGWG1PmpaXbi8nhPQ
# Cp71W49pOGjqpR9byiPuC+280B5DQ26wU4zCcypEMW6+j7jGAva7ggQVeQxSIOiY
# J3Fh7y/k+AL7M1m19MNV59/2CCKuttEJWewBn3OJt0NP1fLZvVZZCd23F/bEdIC6
# h0asBtvbBA3VTrrujAk0GZUb5nATBCXfj7jXhDOMbKYM62i6lU98ROjUaY0lecMh
# 8TV3+E+2ElWV0FboGALV7nnIhqFp8RtOlBNqB2Lw0GuZpZdQnhwzoR7uYYsFaByO
# 9e4mkIPW/nGFp5ryDRQ+NrUSrXd1esznRjZqkFPLxpRx3gc6IfnWMmfgnG5UhqBk
# oIPLAgMBAAGjggFjMIIBXzAfBgNVHSMEGDAWgBQy65Ka/zWWSC8oQEJwIDaRXBeF
# 5jAdBgNVHQ4EFgQUgTKSQSsozUbIxKLGKjkS7EipPxQwDgYDVR0PAQH/BAQDAgGG
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwGgYDVR0g
# BBMwETAGBgRVHSAAMAcGBWeBDAEDMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9j
# cmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5j
# cmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3Rp
# Z28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsG
# AQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOC
# AgEAXzas+/n2cloUt/ALHd7Y/ZcB0v0B7pkthuj2t/A5/9aBSlqnQkoKLRWd5pT9
# xWlKstdL8RYSTPa+kGZliy101KsI92oRAwh3fL5p4bDbnySJA9beXKTgsta0z+M4
# 1bltzCfWzmQR6BBydtP54OksielJ07OXlgYK4fYKyEGakV2B2DZ3mMqAQZeo+JE/
# Y5+qzVRUS4Dq9Rdm05Rx/Z79RzHj6RqGHdO+INI/sVJfspO9jJUJmHKPlQH0mEOl
# SvsUJqqdNr9ysPzcvYQN7O00qF6VKzgWYwV12fYxLhVr4pSyKtJ0NbWYmqP++Csv
# thdLJ2xa5rl2XtqG3atk1mrqgxiIGzGC9YizlCXAIS8IaQLjTLtMKhEw64F5BuFB
# lSrUIPYLk+R8dgydHSZrX4QB9iqZza/ex/DkGKJOmy8qDGamknUmvtlANRNvrqY3
# GnrorRxRYwcqVgZs7X4Y9uPsZHOmbQg2i68Pma51axcrwk1qw1FGQVbpj8KN/xNx
# m9rtntOfq+VFphLFFFpSQZejBgAIxeYc6ieCPDvb5kbE7y0ANRPNNn2d5aonCAXM
# zsA2DksZT9Bjmm2/xSlTMSLbdVB3htDy+GruawYbPoUjK5fIfnqZQQzdWH8OqMMS
# PTo1m+CdLIwXgVREqHodmJ2Wf1lYplRl/1FCC/hH68/45b8wggaCMIIEaqADAgEC
# AhA2wrC9fBs656Oz3TbLyXVoMA0GCSqGSIb3DQEBDAUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKTmV3IEplcnNleTEUMBIGA1UEBxMLSmVyc2V5IENpdHkxHjAc
# BgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0d29yazEuMCwGA1UEAxMlVVNFUlRydXN0
# IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0yMTAzMjIwMDAwMDBaFw0z
# ODAxMTgyMzU5NTlaMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExp
# bWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcgUm9v
# dCBSNDYwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCIndi5RWedHd3o
# uSaBmlRUwHxJBZvMWhUP2ZQQRLRBQIF3FJmp1OR2LMgIU14g0JIlL6VXWKmdbmKG
# RDILRxEtZdQnOh2qmcxGzjqemIk8et8sE6J+N+Gl1cnZocew8eCAawKLu4TRrCoq
# CAT8uRjDeypoGJrruH/drCio28aqIVEn45NZiZQI7YYBex48eL78lQ0BrHeSmqy1
# uXe9xN04aG0pKG9ki+PC6VEfzutu6Q3IcZZfm00r9YAEp/4aeiLhyaKxLuhKKaAd
# QjRaf/h6U13jQEV1JnUTCm511n5avv4N+jSVwd+Wb8UMOs4netapq5Q/yGyiQOgj
# sP/JRUj0MAT9YrcmXcLgsrAimfWY3MzKm1HCxcquinTqbs1Q0d2VMMQyi9cAgMYC
# 9jKc+3mW62/yVl4jnDcw6ULJsBkOkrcPLUwqj7poS0T2+2JMzPP+jZ1h90/QpZnB
# khdtixMiWDVgh60KmLmzXiqJc6lGwqoUqpq/1HVHm+Pc2B6+wCy/GwCcjw5rmzaj
# LbmqGygEgaj/OLoanEWP6Y52Hflef3XLvYnhEY4kSirMQhtberRvaI+5YsD3XVxH
# GBjlIli5u+NrLedIxsE88WzKXqZjj9Zi5ybJL2WjeXuOTbswB7XjkZbErg7ebeAQ
# UQiS/uRGZ58NHs57ZPUfECcgJC+v2wIDAQABo4IBFjCCARIwHwYDVR0jBBgwFoAU
# U3m/WqorSs9UgOHYm8Cd8rIDZsswHQYDVR0OBBYEFPZ3at0//QET/xahbIICL9AK
# PRQlMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9o
# dHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQ2VydGlmaWNhdGlv
# bkF1dGhvcml0eS5jcmwwNQYIKwYBBQUHAQEEKTAnMCUGCCsGAQUFBzABhhlodHRw
# Oi8vb2NzcC51c2VydHJ1c3QuY29tMA0GCSqGSIb3DQEBDAUAA4ICAQAOvmVB7WhE
# uOWhxdQRh+S3OyWM637ayBeR7djxQ8SihTnLf2sABFoB0DFR6JfWS0snf6WDG2gt
# CGflwVvcYXZJJlFfym1Doi+4PfDP8s0cqlDmdfyGOwMtGGzJ4iImyaz3IBae91g5
# 0QyrVbrUoT0mUGQHbRcF57olpfHhQEStz5i6hJvVLFV/ueQ21SM99zG4W2tB1ExG
# L98idX8ChsTwbD/zIExAopoe3l6JrzJtPxj8V9rocAnLP2C8Q5wXVVZcbw4x4ztX
# LsGzqZIiRh5i111TW7HV1AtsQa6vXy633vCAbAOIaKcLAo/IU7sClyZUk62XD0VU
# nHD+YvVNvIGezjM6CRpcWed/ODiptK+evDKPU2K6synimYBaNH49v9Ih24+eYXNt
# I38byt5kIvh+8aW88WThRpv8lUJKaPn37+YHYafob9Rg7LyTrSYpyZoBmwRWSE4W
# 6iPjB7wJjJpH29308ZkpKKdpkiS9WNsf/eeUtvRrtIEiSJHN899L1P4l6zKVsdrU
# u1FX1T/ubSrsxrYJD+3f3aKg6yxdbugot06YwGXXiy5UUGZvOu3lXlxA+fC13dQ5
# OlL2gIb5lmF6Ii8+CQOYDwXM+yd9dbmocQsHjcRPsccUd5E9FiswEqORvz8g3s+j
# R3SFCgXhN4wz7NgAnOgpCdUo4uDyllU9PzCCBqUwggUNoAMCAQICEFOGK0nCUn5D
# xL7vamlI8k0wDQYJKoZIhvcNAQELBQAwVzELMAkGA1UEBhMCR0IxGDAWBgNVBAoT
# D1NlY3RpZ28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJsaWMgQ29kZSBT
# aWduaW5nIENBIEVWIFIzNjAeFw0yNjAyMTcwMDAwMDBaFw0yNzAyMTcyMzU5NTla
# MIG1MRAwDgYDVQQFEwc3OTUxNjgwMRMwEQYLKwYBBAGCNzwCAQMTAlVTMRswGQYL
# KwYBBAGCNzwCAQITCk5ldyBNZXhpY28xHTAbBgNVBA8TFFByaXZhdGUgT3JnYW5p
# emF0aW9uMQswCQYDVQQGEwJVUzETMBEGA1UECAwKTmV3IE1leGljbzEWMBQGA1UE
# CgwNQXJ0SXNXYXIsIExMQzEWMBQGA1UEAwwNQXJ0SXNXYXIsIExMQzCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMVFeTYQb98NCxG5kyp+3X9znsqnixKZ
# zbUdGu0Xi4rjRRryPd3aWUND6TphmpEqb5K1HK3OMb+HMgH2Umol43qRxngZFN8U
# VJYLL6M9ByK9zC5wr7c4dEfH2CkAXrF/PaZFBl7apuOpKg+5rTcEZFd/8xDZkznS
# gpLEmUBjIP8L1hEKKPWDHMEZZVAh0AX1KW9v/Xm5TbXLvtffqr7SPOuVjkOGzZs1
# 3bcK7Dq9OCfLBGaOKNbUtU87bVAUpL5uLsunRy9oNISvBsvbaRAP3GuO2IVRDwol
# QjSgu/onViW7of6RcZAO446lObSC/gjC/lM3AxVgVasZlwHrSOwxCoiUaK3tgaZJ
# X05W2wERm4oEGbpE03cTfXzfpPfoil9+uzugKR8Pqjk//xeVJMyXn+AcrC7Zq/fS
# 5r2UMoRex5xWV+Bb5EHZ6bdbGcfMtKDlz3vvZe0vB6S/vGsG83V6jGtVM/Co36dE
# rVmhSa7XAahxLsZcTxhlXEpkB6B1qaUuURPHgLFEh2r5mYssjMYrO993Q9A1fiwm
# rLAkhc9nwzLPQrrw1Sxx4d8sBlEf3aGYJe41NOLT7I6359adyxhDFr7/vuQCfMby
# 5MRHphYuHVlDQPMbqG+wiTWCwiYVMiuDQJvuYYGfgYfauSVf3AA9inrabPDW6KkZ
# A+mJPlCrMFeLAgMBAAGjggGMMIIBiDAfBgNVHSMEGDAWgBSBMpJBKyjNRsjEosYq
# ORLsSKk/FDAdBgNVHQ4EFgQUZ8OCbUd0wHpetRPAMtcd9WTyW/8wDgYDVR0PAQH/
# BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwSQYDVR0g
# BEIwQDA1BgwrBgEEAbIxAQIBBgEwJTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0
# aWdvLmNvbS9DUFMwBwYFZ4EMAQMwSwYDVR0fBEQwQjBAoD6gPIY6aHR0cDovL2Ny
# bC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25pbmdDQUVWUjM2LmNy
# bDB7BggrBgEFBQcBAQRvMG0wRgYIKwYBBQUHMAKGOmh0dHA6Ly9jcnQuc2VjdGln
# by5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nQ0FFVlIzNi5jcnQwIwYIKwYB
# BQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBCwUAA4IB
# gQCf2jswDbgZjrjEG2Nb4iHpaUJMxZBjvHEWC3fkIdFgDsNtqUudrc+paTNrR7FD
# 2J8Hu1srS75qRTliebxUGBl/QvIaSt1kkRnhJQCCD4gYNoncXdIeaFGHEAfQK+HX
# UCY72y1HdC3CMGINZTQSo+wSNJXJPnSMAOe2J0D9Jk+qAkbn1CSjtSX4KHu4Hvfp
# 6dYEKyJx2TfI+Ax+JoOq/v6rq2ca0vFuc3Jmwk5T4vqwjZVR/dgy5SAH+WmOqkny
# KnMmWv5hfTeffQsXwmMMQJUSFN7wsvgzgf1iIcW6jktS4+fKiKKScJLOh/Sxnomi
# 0JclNyRood43pyOwmJ90xn7/juj1JdHH4Tf9MNeay8vLDqLpwVSVYkuuxm9CO6uv
# OB2L3wd1Fdw4tFlboHHBOVu7Uo6HkFKwN2kcHCN/iExEkG3g0QZUFTUnHoRUmIov
# u82ODUIAo8E8ej7WOdZQBLnpRSr2fBq/VhvoSfcKe/PE8ZdL8RO+dc5Dca7u0HeA
# BsswgganMIIEj6ADAgECAhEAkKwIciD9xafEa1zHDfc9BjANBgkqhkiG9w0BAQwF
# ADBXMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS4wLAYD
# VQQDEyVTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIFJvb3QgUjQ2MB4XDTI2
# MDMyNTAwMDAwMFoXDTQxMDMyNDIzNTk1OVowVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSNDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCu5EqiAa2CHGL5Zi1bmgPM8NUXwYZJ+BtQqHps43GLTC+sjVLypsBh+8uv+TLk
# gtVGD//vSmA0qrzELf9YRCh2MTAA/aGaQZKGg0BRCmziR3pbCnvgWjtGXBDUyn3j
# 3K2lZAO8KxgFtlxwOYEAkL+CCqK4v9zzTl8ZwzDpPMiDIFa5THk8an1ieF5I09cX
# NrPQw+1ER1liThaG0z6FrOpqwxZWmPRZQBw2E32878UB1bL0Zp91vuWZgsMpNNiP
# CoBj0/1F+LE8+NRokfqacFI0F2tftrRB2W7HQClLR9zjxFbWb5be2rceIfNyHUUf
# KGIvMI2NzoxSlxXnFqUG887D8W1Cj8DFok688JKxWvHR/9aQykSbd+9Vutj36ij2
# sgq/125wTpUZ/AgC0ph50bRs7gFrUyaXE9wSsOqMvCCC+sEm7vd/BemSG0TSHNXS
# myCba+FCzekeWX03TRIcF3Laqd0Rw24OH7jpei4zaGhcI7nfdhBA4c8RScxNY6je
# HLHHmSMMTk9Wqn7H4dLhUBP5YEwbgbN4uv1i9ltTnHli8t1xHV0StX9BFgrnmunT
# X19kUXY1H5ORJbRZyZDdvm1oZyteDj0SnMozr+YSmdIleDUTXdfoY7b2taz8s2+Q
# bOxLxcahEIYGWzqu6h955tKwcANHcZ4gTmAhT3btuOiQsQIDAQABo4IBbjCCAWow
# HwYDVR0jBBgwFoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFDp0pQxn
# xkJQwv21/Me7KTSC9Hq5MA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/
# AgEAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMCMGA1UdIAQcMBowCAYGZ4EMAQQCMA4G
# DCsGAQQBsjEBAgEDCDBMBgNVHR8ERTBDMEGgP6A9hjtodHRwOi8vY3JsLnNlY3Rp
# Z28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3RhbXBpbmdSb290UjQ2LmNybDB8Bggr
# BgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0dHA6Ly9jcnQuc2VjdGlnby5jb20v
# U2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzAB
# hhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEAMt5S
# R2bxngNm+N8oc6Gq76Gx1c235fkX7jw8Ho9MAkJGADerHE7dhsBXttqmzgr/7ZZa
# hZSykGRPhPY1crj028kB8KzO0dKC2qQBAwtfgqMLKkkX/6bYq2uT33eD6ByAp2/X
# KD0LcmZh0kKecvSBr6ln9ajX6u1dnx2fA7xEKy1M3qBhfQSUWLtjs2nFt0ELVLpt
# zTlX9ID0cL+iOPfdboZ3CelT+JXKVKR2Sge0d4YiFAtPZkfSo8z1Z1x7y/Z9mwMI
# lBAnyuWXs4YsNuxdrYIt/QxE31PDOJ9DesS4Bc7H9OTORlEV/AvfiF/VepKZpira
# 1MzLYuCw+uoLZn/pkpvd+CvNTS+mEHjBJNa6WK1j8qXFu+jIq+sG9QILHiyB6p/x
# pHrkJu8zkw393+VqF9eKlTY2VjRxdycZLrVemZ4Yp3wi33b+W58CllH3HqjmowlZ
# 7SOrgmx8YwYOkgrHsXOQHyBp6O4FRb8In0+FzjT7ElGie9V7CfhL3IlVFZ4zjuKs
# ZtH1iU3fGu4z/JnOGT6sCb0BbTqe/uhvpFCQBdH5xPGIA/LrbQUXjU2tWJgHhTIq
# nN/HvHyOHi5tM4zP3nhgh2rJ6Kqq2xsHBeNYs/R18xQ8DeIg+c90Eoaeh0YlN1KU
# 8AyYol3K9M+qY5ez8syd/7ZlrRnoVewgH3P1pcswggbiMIIEyqADAgECAhEA507y
# VbBQT/rbpt/3/IujFTANBgkqhkiG9w0BAQwFADBVMQswCQYDVQQGEwJHQjEYMBYG
# A1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBU
# aW1lIFN0YW1waW5nIENBIFI0MTAeFw0yNjAzMjUwMDAwMDBaFw0zNzA2MjQyMzU5
# NTlaMHIxCzAJBgNVBAYTAkdCMRcwFQYDVQQIEw5HcmVhdGVyIExvbmRvbjEYMBYG
# A1UEChMPU2VjdGlnbyBMaW1pdGVkMTAwLgYDVQQDEydTZWN0aWdvIFB1YmxpYyBU
# aW1lIFN0YW1waW5nIFNpZ25lciBSMzcwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQCy/8NtS9xQ2UUtBRF32bj7VK3n4m50Uqjk/zTciSziYV40H1LKah0/
# oEklYG42E4VCP3DvsBUB6DmpCkDZ0jCnZBPIEevaH15ZJOQwFWP2ZXr5YjlJpb68
# Nlbs+ElNvKx32/1YHde3qqUSLybjulxPLz6T85+HOIqK7M1Bep8LspyhEP/q6nw5
# kGxTSrGvufmeH+JF8CnVBcVMFA40FlIYh0cDJVFhhfTfdWgLy/vWuLMQoKkf3s/F
# vByf16r0rtbyHm/iemwxSioJL9zyZDDKUNAbHXl0dhXo2VxUV2NcPXWXuoKsjL+6
# cfk6Vm2DHnxAlFdFsaBDIF1JOkSnC6PeLlBznZn2buF3vIIYJcq6N/zeFRCk4/HX
# Dz7zgRsRRMdUB+rhyk5FoZaBjw0nLq3GZ3fClLUx5es5pUAxzNODMBn7JkFYip2B
# AGBPER5eV0ROhk6tGTG+fUiMiV+vgjg1YnP5FvnYWyEtWeQD/B2hp3vz0RvtdkM0
# p3igyadzrfpOBq5ppVk/YsuhTQkP99ivneHAGfi5e7lmxJ+meoBPrRLuzMmb81rz
# zbESjJHMsn5RVtc6Ucs7rcMqQC13PUIO7BbGBETV2ufCmV6lPTp3P7XJOvmnUCRT
# PbVvMTpxP/z+SOHg4/OCBhiqs4FA9+4oQvlkk9w32NGASli9GWrm5wIDAQABo4IB
# jjCCAYowHwYDVR0jBBgwFoAUOnSlDGfGQlDC/bX8x7spNIL0erkwHQYDVR0OBBYE
# FGEQ6XoSr1HEhdTyz6R0D1DNIK/4MA4GA1UdDwEB/wQEAwIGwDAMBgNVHRMBAf8E
# AjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMEoGA1UdIARDMEEwCAYGZ4EMAQQC
# MDUGDCsGAQQBsjEBAgEDCDAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28u
# Y29tL0NQUzBKBgNVHR8EQzBBMD+gPaA7hjlodHRwOi8vY3JsLnNlY3RpZ28uY29t
# L1NlY3RpZ29QdWJsaWNUaW1lU3RhbXBpbmdDQVI0MS5jcmwwegYIKwYBBQUHAQEE
# bjBsMEUGCCsGAQUFBzAChjlodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29Q
# dWJsaWNUaW1lU3RhbXBpbmdDQVI0MS5jcnQwIwYIKwYBBQUHMAGGF2h0dHA6Ly9v
# Y3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4ICAQAD6j2N0azN+hl6k6bK
# B5/U6VuSOs93ZBb3Pczy9VtBIKu4947Z5GwL0aFngIxl+GSuLFrJgPruBCRvKJEJ
# sm7kv+LQ1COVCEG9tZ+IRtr4ocUoa53lgdFaENlS0N4wgkZkbQEPv+x+1lSjYh+T
# 4JeL9mUznT7Erc6Sp5dWLka5sMP/m3GZi6oJPdPcsCKWagH7m2H2xDGIyHJC5PdH
# 9phvi/KmhkktiSVTNNqVeV5bWdX2zhRE6UTfz0IcMoCL996lFIydXxOCE4MNDHDM
# 0as4lnTiT/KHMccO6l8c9TnUVgmpci9ar1IABZ2U1XUkYjGGSn9MC3EHDP9V39Vu
# BVvZ33/BEV/EWSRrf07T7jFplKX+gQr/UOqPGMlE7ZJ72UaUkNJy7bVl3bcLKzdp
# jIHzLkf/4MVa1V7w8wqCv5W4gOnRGTlud5UMARbRM8BPxR/CXYXoMmIOD8pmTk2a
# xgRL4LG8XtuchISdCHRmtacAmLGq5XSYSVTHTXADlO48iDKh3HM2r98LSF6f0sG1
# 2d8V9Jn7C3wDUieOxuKj4MdWrW+hiJU2kF87v6eH00HgCFFc2V0+CvfOCMn7juzS
# 41jLaINcBlKWQ/fKb/uDLfWOW73z1I2lFY7Xj8tQ1XYtK5eREjWItM8jpl1cbQOc
# 88btR+0XS2TmboE/141+va2PWzGCBkQwggZAAgEBMGswVzELMAkGA1UEBhMCR0Ix
# GDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJs
# aWMgQ29kZSBTaWduaW5nIENBIEVWIFIzNgIQU4YrScJSfkPEvu9qaUjyTTANBglg
# hkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3
# DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEV
# MC8GCSqGSIb3DQEJBDEiBCB/q8ZEzsdYBLddQ3pO9zwEJYBo25nkAab4kK7iDSah
# vjANBgkqhkiG9w0BAQEFAASCAgAeewZJEA+KzV5aCO66ShC18/MtcqNA+kIZjdPK
# NbxqA0W9ZXef3dMtwJ7IGN6yw3qxLiq6d5yEovwqwhJ4HczitPXLOXjUz87UPofk
# +bXsZHW59FjTqlcUdtEvQdZ9xLWLGRk6flmAD2aa3HAVv58DsPLj25Rvgy0e5v09
# nyxUS2Vq0rc8zVrbVoSmFwhbeS6AdAvVwYkhabRPFbwRW48/gwCVOEMbiW8gFVrK
# 11/ai70xdliILepLH3Iq+Xg122X8EEe5MBDHbeoi4LF+nxCkZiEoRmCgQiAo0vKO
# j3kYWfqBFTWuKHNGtH4/hged9rP65AUcx14lyQ0t+xhZdnKOxsJnUM4YzNNX5naX
# FWhXEss6ZTPQB3oyZcX7ySws+hKtKM+uzfNdpuVfQx78bjBSIOTyPA9YPLpHXjL+
# zdgMbtSZQTj3NWMUS2q2jai1psxJ+XoZ3wIZEk1BR6p+RSKvdaJdpXtBzrXCKdab
# MRAeSayHPR8anCcUEtCNH6rFbje7EUvkfolHA3jYt3J73nxcv7H9WuWVQUzdy3AO
# mGBE61lqk/t73J3huvbebB5IhUx9uZkpYzBdA2GWvi2Yx5sahzxXQeST7YJaKWRJ
# 98Psb/zUc+TYz7v7ZHmR41lUjHYU76BuQQGJf/MamubsylLyV14oqhB3Seny8Cvh
# smW3OKGCAyMwggMfBgkqhkiG9w0BCQYxggMQMIIDDAIBATBqMFUxCzAJBgNVBAYT
# AkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28g
# UHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQxAhEA507yVbBQT/rbpt/3/IujFTAN
# BglghkgBZQMEAgIFAKB5MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZI
# hvcNAQkFMQ8XDTI2MDgwNDAyNTUxMVowPwYJKoZIhvcNAQkEMTIEMAL34Wky8sJ2
# meBKkAO9iIjqZRBHWA6FlrLG4/4nstoRSHsiqAXBYU4pTLQDRqE7SzANBgkqhkiG
# 9w0BAQEFAASCAgAR47RrCrqy7hyx0Udeu0+cxCTV4kYJLfcOVp00Wmj5j5rTgPwA
# 3hrNpUI0msTIgRMeP2yAw9L6O1jagkiO3pkgyHyur2eFpIxHNkQkw1E7SB2xu5bJ
# LSqF6n6NtRUYi5eCQPoz15eSkIolBk7s0fKIMedahhYK/1Y0w6SCOXnyNWih80Z/
# NNhXHkRvGTzKjXPmCyHi42pQNXBAcfztS/yNvfYoptsmmiW6huufv5lIk3uveSPN
# xDIPdmfvOb86eh0LMqhW7mg/piMTMVSP3r9ZatrC40RQaPJFkpuL+T+gxOBejlIm
# jucp2ZxeDLC8Lul7VYSoj6HYBXBGqLNpe90GRH+btizSASFEtkCO0RJVklSbQOsY
# Hr6D5vB46GGvKdAJ80YX3oEiAKhJybibwdn8hqaxWUcNwWn44bAYCHyeama6v1Td
# NcSwwZ7bIccJuROwOmW8cQe+7rvSjCw6tyb/l/IF77Xur50EY5kJukxEMnHxN2lw
# 3DR6iqDMN8qYz3ZBp9B4p18l89rrSEyH+dZw7kluY90DsQFfN2oMBvw0yBt5hED6
# KYAkVteHBcdofNgAKE+cmf0lXYXJ0CT1C1EQ4vv5P0RmmzMbsZq01+Y5+Zvi1cjv
# NZ2vgt8BkQFfNoA9+MYaZrmnz24u8wik98dlSzJLdvQi0Bns42GYRAu7hA==
# SIG # End signature block
