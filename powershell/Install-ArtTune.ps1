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

$script:Version = "1.0"
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
    Write-Host "$m$L$(Center-Text 'updated Mar 2026' $w)$L" -ForegroundColor Yellow
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
    Write-Host "$(Center-Text 'Initial Release: Guided Install for VM+HiFi Cable, GC7, & G8.' $w)" -ForegroundColor DarkGray -NoNewline
    Write-Host "$L" -ForegroundColor Yellow
    Write-Host "$m$L" -ForegroundColor Yellow -NoNewline
    Write-Host "$(Center-Text 'LEQ Control Panel Release.' $w)" -ForegroundColor DarkGray -NoNewline
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
        [bool]$SoundControlInstalled = $true
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
    Write-Host (& $p "")
    Write-Host (& $p "Installed:")
    Write-Host (& $p "  $([char]0x2713) Hi-Fi Cable       $([char]0x2713) ReaPlugs")
    Write-Host (& $p "  $([char]0x2713) Voicemeeter       $([char]0x2713) E-APO")
    if ($SoundControlInstalled) {
        Write-Host (& $p "  $([char]0x2713) HeSuVi            $([char]0x2713) LEQ Control Panel")
    } else {
        Write-Host (& $p "  $([char]0x2713) HeSuVi            [!] LEQ Control Panel") -ForegroundColor Yellow
        Write-Host (& $p "                         (download from GitHub)") -ForegroundColor Yellow
    }
    Write-Host (& $p "")
    Write-Host (& $p $s) -ForegroundColor DarkGray
    Write-Host (& $p "")
    Write-Host (& $p "Press [s] below to launch LEQ Control Panel")
    Write-Host (& $p "and Device Selector, then follow the video.")
    Write-Host (& $p "")
    Write-Host (& $p "Press [b] for artiswar.io - Something easier") -ForegroundColor DarkGray
    Write-Host (& $p "coming soon...") -ForegroundColor DarkGray
    Write-Host (& $p "")
    Write-Host "$m$([char]0x255A)$b$([char]0x255D)" -ForegroundColor Green
    Write-Host ""

    # Interactive launch options (loops until quit or back)
    while ($true) {
        $menuMargin = Write-CenteredBlock @(
            @{ Text = '[s] Open LEQ Control Panel'; Color = 'White' }
            @{ Text = '[b] artiswar.io - Something easier coming soon...'; Color = 'DarkGray' }
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
                Start-Process "https://artiswar.io/arttunekit.html"
                Write-Host "$($script:BoxMargin)Opened in browser." -ForegroundColor Green
                Write-Host ""
            }
            'm' { return 'mainMenu' }
            'q' { return 'quit' }
            default { Write-Host "$($script:BoxMargin)Invalid choice." -ForegroundColor Red; Write-Host "" }
        }
    }
}

function Write-DeviceCompletion {
    <#
    .SYNOPSIS
        PATH A completion box -- approved device install.
    #>
    param(
        [switch]$IncludeCreativeApp,
        [bool]$SoundControlInstalled = $true
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
    Write-Host (& $p "")
    Write-Host (& $p "Installed:")
    Write-Host (& $p "  $([char]0x2713) ReaPlugs          $([char]0x2713) E-APO")
    if ($SoundControlInstalled) {
        Write-Host (& $p "  $([char]0x2713) HeSuVi            $([char]0x2713) LEQ Control Panel")
    } else {
        Write-Host (& $p "  $([char]0x2713) HeSuVi            [!] LEQ Control Panel") -ForegroundColor Yellow
        Write-Host (& $p "                         (download from GitHub)") -ForegroundColor Yellow
    }
    if ($IncludeCreativeApp) {
        Write-Host (& $p "  $([char]0x2713) Creative App")
    }
    Write-Host (& $p "")
    Write-Host (& $p $s) -ForegroundColor DarkGray
    Write-Host (& $p "")
    if ($IncludeCreativeApp) {
        Write-Host (& $p "Press [s] below to open LEQ Control Panel,")
        Write-Host (& $p "Device Selector, Creative App, and the")
        Write-Host (& $p "Art Tune approved devices page.")
        Write-Host (& $p "")
        Write-Host (& $p "Choose your device on the Art Tune approved")
        Write-Host (& $p "devices page and continue the video guide.")
    } else {
        Write-Host (& $p "Press [s] below to launch LEQ Control Panel")
        Write-Host (& $p "and Device Selector, then follow the video.")
    }
    Write-Host (& $p "")
    Write-Host (& $p "Press [b] for artiswar.io - Something easier") -ForegroundColor DarkGray
    Write-Host (& $p "coming soon...") -ForegroundColor DarkGray
    Write-Host (& $p "")
    Write-Host "$m$([char]0x255A)$b$([char]0x255D)" -ForegroundColor Green
    Write-Host ""

    # Interactive launch options (loops until quit or back)
    while ($true) {
        $sLabel = if ($IncludeCreativeApp) { '[s] Open LEQ Control Panel, Creative App + Guide' } else { '[s] Open LEQ Control Panel' }
        $menuMargin = Write-CenteredBlock @(
            @{ Text = $sLabel; Color = 'White' }
            @{ Text = '[b] artiswar.io - Something easier coming soon...'; Color = 'DarkGray' }
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
                $scFound = Test-Path $scExe
                if ($scFound) { Start-Process $scExe }
                else {
                    Write-Host "$($script:BoxMargin)LEQ Control Panel not found. Download it from:" -ForegroundColor Yellow
                    Write-Host "$($script:BoxMargin)https://github.com/ArtIsWar/LEQControlPanel/releases" -ForegroundColor Yellow
                }
                if ($IncludeCreativeApp) {
                    # Launch Creative App
                    $caExe = @(
                        "$env:ProgramFiles\Creative\Creative App\Creative.App.exe",
                        "${env:ProgramFiles(x86)}\Creative\Creative App\Creative.App.exe"
                    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($caExe) { Start-Process $caExe }
                    else { Write-Host "$($script:BoxMargin)Creative App not found." -ForegroundColor Yellow }
                    # Open approved devices page
                    Start-Process "https://artiswar.io/devices"
                    if ($scFound) {
                        Write-Host "$($script:BoxMargin)Launched LEQ Control Panel, Creative App, and setup guide." -ForegroundColor Green
                    } else {
                        Write-Host "$($script:BoxMargin)Launched Creative App and setup guide." -ForegroundColor Green
                    }
                } else {
                    if ($scFound) {
                        Write-Host "$($script:BoxMargin)Launched LEQ Control Panel." -ForegroundColor Green
                    }
                }
                Write-Host ""
            }
            'b' {
                Start-Process "https://artiswar.io/arttunekit.html"
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
        [string[]]$RemovedComponents
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
    Write-Host (& $p "")
    Write-Host (& $p "Your audio devices have been restored")
    Write-Host (& $p "to their original names. You may need")
    Write-Host (& $p "to set your Windows default audio")
    Write-Host (& $p "device back to your headphones/DAC.")
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
        @{ Num = '1'; Tool = 'Voicemeeter + Hi-Fi Cable'; Dev = 'Vincent Burel (VB-Audio)'; Url = 'https://shop.vb-audio.com' }
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

function Install-Winget {
    <#
    .SYNOPSIS
        Ensures winget is available, installing from GitHub if needed.
        Non-fatal: warns and continues if all install methods fail.
    #>
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $null = Write-CenteredBlock @(@{ Text = 'winget: OK'; Color = 'Green' })
        return
    }

    $null = Write-CenteredBlock @(
        @{ Text = 'winget (Windows Package Manager) is required to install some components.'; Color = 'DarkGray' }
        @{ Text = 'winget: not found, installing...'; Color = 'Yellow' }
    )

    # -- Attempt 1: Add-AppxProvisionedPackage (works on standard Windows) -----
    $msixPath    = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
    $licensePath = "$env:TEMP\Microsoft.DesktopAppInstaller_License.xml"

    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $msixUrl = ($release.assets | Where-Object { $_.name -match '\.msixbundle$' }).browser_download_url
        $licenseUrl = ($release.assets | Where-Object { $_.name -match 'License.*\.xml$' }).browser_download_url

        if (-not $msixUrl -or -not $licenseUrl) {
            throw "Could not find winget release assets on GitHub"
        }

        Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing
        Invoke-WebRequest -Uri $licenseUrl -OutFile $licensePath -UseBasicParsing

        Add-AppxProvisionedPackage -Online -PackagePath $msixPath -LicensePath $licensePath -ErrorAction Stop | Out-Null

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")

        Remove-Item $msixPath, $licensePath -Force -ErrorAction SilentlyContinue

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $null = Write-CenteredBlock @(@{ Text = 'winget: installed successfully'; Color = 'Green' })
            return
        }
        throw "winget installed but not found in PATH"
    }
    catch {
        $provisionError = $_
        Remove-Item $msixPath, $licensePath -Force -ErrorAction SilentlyContinue
    }

    # -- Attempt 2: Add-AppxPackage with dependencies (LTSC / IoT / debloated) -
    $null = Write-CenteredBlock @(
        @{ Text = 'Provisioned install failed, trying Add-AppxPackage with dependencies...'; Color = 'Yellow' }
    )

    $vclibsPath  = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $nupkgPath   = "$env:TEMP\Microsoft.UI.Xaml.2.8.6.zip"
    $extractDir  = "$env:TEMP\Microsoft.UI.Xaml"

    try {
        # Download the msixbundle if it wasn't already downloaded
        if (-not (Test-Path $msixPath)) {
            if (-not $msixUrl) {
                $release = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
                $msixUrl = ($release.assets | Where-Object { $_.name -match '\.msixbundle$' }).browser_download_url
            }
            if (-not $msixUrl) { throw "Could not find winget msixbundle on GitHub" }
            Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing
        }

        # Download VCLibs
        Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $vclibsPath -UseBasicParsing

        # Download UI.Xaml nupkg (it's a zip -- use .zip extension for Expand-Archive compat)
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6" -OutFile $nupkgPath -UseBasicParsing

        # Extract and find the x64 appx dynamically (internal paths shift between versions)
        Expand-Archive $nupkgPath $extractDir -Force
        $uixamlAppx = Get-ChildItem $extractDir -Recurse -Filter "Microsoft.UI.Xaml.2.8*.appx" |
            Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1

        if (-not $uixamlAppx) {
            throw "Could not find x64 UI.Xaml appx in NuGet package"
        }

        Add-AppxPackage -Path $msixPath -DependencyPath @($vclibsPath, $uixamlAppx.FullName) -ErrorAction Stop

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $null = Write-CenteredBlock @(@{ Text = 'winget: installed successfully'; Color = 'Green' })
            return
        }
        throw "winget installed but not found in PATH"
    }
    catch {
        # Both methods failed -- warn and continue (winget is only needed for Creative App)
        Write-Host ""
        $null = Write-CenteredBlock @(
            @{ Text = 'WARNING: Could not install winget automatically.'; Color = 'Yellow' }
            @{ Text = 'Some optional components (Creative App) may need manual install.'; Color = 'DarkGray' }
            @{ Text = ''; Color = 'DarkGray' }
            @{ Text = '[d] Open winget download page'; Color = 'Yellow' }
            @{ Text = 'Press any other key to continue without winget.'; Color = 'DarkGray' }
        )
        Write-Host ""
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
        if ($key -eq 'd' -or $key -eq 'D') {
            Start-Process 'https://aka.ms/getwingetpreview'
            Write-Host ""
            $null = Write-CenteredBlock @(@{ Text = 'Opened in browser.'; Color = 'Green' })
            Write-Host ""
        }
    }
    finally {
        Remove-Item $msixPath, $licensePath, $vclibsPath, $nupkgPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
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

function Restart-AudioServices {
    <#
    .SYNOPSIS
        Restarts Windows audio services using Restart-Service -Force,
        which handles the Audiosrv/AudioEndpointBuilder dependency graph atomically.
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
        param($url, $outFile)
        $ProgressPreference    = 'SilentlyContinue'
        $ErrorActionPreference = 'Stop'
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
    $results  = @{}   # Key -> OutFile or $null

    # -- Helper: start an IWR download in a runspace ---------------------------
    $startIwr = {
        param($key, $url, $outFile)
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript($iwrScript).AddArgument($url).AddArgument($outFile)
        $iwrJobs[$key] = @{ PS = $ps; Handle = $ps.BeginInvoke() }
        $state[$key]   = 'downloading'
        $started[$key] = [datetime]::UtcNow
    }

    # -- Helper: start a BITS download -----------------------------------------
    $startBits = {
        param($key, $baseUrl, $outFile, $mirrorIdx)
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

    # -- Phase C: Polling loop with single progress bar -----------------------
    $fi = 0
    $m = $script:BoxMargin
    $pad = $script:ScreenWidth
    $total = if ($TotalCount -gt 0) { $TotalCount } else { $Specs.Count }
    $skipped = $total - $Specs.Count

    # Print what we're about to download
    $nameList = ($Specs | ForEach-Object { $_.DisplayName }) -join ', '
    Write-Host "$m  Downloading: $nameList" -ForegroundColor DarkGray

    try {

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
                try {
                    $ij.PS.EndInvoke($ij.Handle)
                    $spec = $Specs | Where-Object { $_.Key -eq $key }
                    if ((Test-Path $spec.OutFile) -and (Get-Item $spec.OutFile).Length -gt 0) {
                        $fileLen = (Get-Item $spec.OutFile).Length
                        $sizes[$key] = if ($fileLen -ge 1MB) { "[{0:N1} MB]" -f ($fileLen / 1MB) }
                                       elseif ($fileLen -ge 1KB) { "[{0:N0} KB]" -f ($fileLen / 1KB) }
                                       else { "" }
                        $state[$key] = 'done'
                    } else {
                        throw "File missing or empty after download"
                    }
                } catch {
                    $state[$key] = 'error'
                    $errors[$key] = "$_"
                }
                $ij.PS.Dispose()
                $iwrJobs.Remove($key)
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
                    $sizes[$key] = if ($fileLen -ge 1MB) { "[{0:N1} MB]" -f ($fileLen / 1MB) }
                                   elseif ($fileLen -ge 1KB) { "[{0:N0} KB]" -f ($fileLen / 1KB) }
                                   else { "" }
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
                $dlSpec = $Specs | Where-Object { $_.Key -eq $key }
                $dlTimeout = if ($dlSpec.TimeoutSec) { $dlSpec.TimeoutSec } else { 120 }
                if ($elapsed -gt $dlTimeout) {
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
                    $errors[$key] = "Download timed out ($($dlTimeout)s)"
                }
            }
        }

        # -- Render single progress line ---------------------------------------
        $doneCount = @($state.Values | Where-Object { $_ -eq 'done' -or $_ -eq 'error' }).Count + $skipped
        $bar = Get-ProgressBar -Width 30 -Percent -1 -Frame $fi
        $line = "$m  Downloading $doneCount/$total $bar"
        Write-Host "`r$($line.PadRight($pad))" -NoNewline -ForegroundColor DarkGray

        Start-Sleep -Milliseconds 250
        $fi++
    }

    # -- Print final results per item -----------------------------------------
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

    } finally {
        # -- Cleanup (always runs, even on exception) --------------------------
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
        If set, includes Hi-Fi Cable and Voicemeeter (PATH B: DAC/amp/onboard).
        If not set, downloads shared components only (PATH A: approved device).
    #>
    param(
        [switch]$IncludeVirtualAudio
    )

    if (-not (Test-Path $script:TempPath)) {
        New-Item -ItemType Directory -Path $script:TempPath -Force | Out-Null
    }

    $files = @{
        HiFiCable    = $null
        Voicemeeter  = $null
        ReaPlugs     = $null
        EAPO         = $null
        HeSuVi       = $null
        SoundControl = $null
    }

    # -- Detect what is already installed ------------------------------------
    $reaplugsDlls = @(Get-ChildItem "${env:ProgramFiles}\VSTPlugins\ReaPlugs\*.dll" -ErrorAction SilentlyContinue)
    $skipReaPlugs = ($reaplugsDlls -and $reaplugsDlls.Count -ge 5)
    $skipEAPO = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO\config")
    $skipHeSuVi = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO\config\HeSuVi")

    # -- Ensure BITS service is available for SourceForge downloads -----------
    if (-not $skipEAPO -or -not $skipHeSuVi) {
        try {
            Ensure-BitsRunning
        } catch {
            throw "BITS service could not be started. If this is a managed PC, ask your IT admin to enable BITS."
        }
    }

    if ($IncludeVirtualAudio) {
        $skipHiFiCable = [bool](Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*Hi-Fi*" -or $_.Name -like "*HiFi*" })
        $skipVoicemeeter = Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} "VB\Voicemeeter\voicemeeter.exe")
    }

    # -- Print skip messages for already-installed components ----------------
    if ($IncludeVirtualAudio) {
        if ($skipHiFiCable)  { Write-Host "$($script:BoxMargin)Hi-Fi Cable already installed, skipping download." -ForegroundColor DarkGray }
        if ($skipVoicemeeter) { Write-Host "$($script:BoxMargin)Voicemeeter already installed, skipping download." -ForegroundColor DarkGray }
    }
    if ($skipReaPlugs) { Write-Host "$($script:BoxMargin)ReaPlugs already installed, skipping download." -ForegroundColor DarkGray }
    if ($skipEAPO)     { Write-Host "$($script:BoxMargin)Equalizer APO already installed, skipping download." -ForegroundColor DarkGray }
    if ($skipHeSuVi)   { Write-Host "$($script:BoxMargin)HeSuVi already installed, skipping download." -ForegroundColor DarkGray }

    # -- Build download specs ------------------------------------------------
    $totalComponents = if ($IncludeVirtualAudio) { 6 } else { 4 }
    $specs = @()

    if ($IncludeVirtualAudio) {
        if (-not $skipHiFiCable) {
            $files.HiFiCable = Join-Path $script:TempPath "HiFiCableSetup.zip"
            $specs += @{
                Key         = 'HiFiCable'
                DisplayName = 'Hi-Fi Cable'
                OutFile     = $files.HiFiCable
                Method      = 'IWR'
                Url         = 'https://download.vb-audio.com/Download_CABLE/HiFiCableAsioBridgeSetup_v1007.zip'
                BaseUrl     = $null
                UrlResolver = $null
                FallbackUrl = $null
                TimeoutSec  = 120
            }
        }

        if (-not $skipVoicemeeter) {
            $files.Voicemeeter = Join-Path $script:TempPath "VoicemeeterSetup.zip"
            $specs += @{
                Key         = 'Voicemeeter'
                DisplayName = 'Voicemeeter'
                OutFile     = $files.Voicemeeter
                Method      = 'IWR'
                Url         = $null
                BaseUrl     = $null
                UrlResolver = $script:VoicemeeterUrlResolver
                FallbackUrl = $null
                TimeoutSec  = 135
            }
        }
    }

    if (-not $skipReaPlugs) {
        $files.ReaPlugs = Join-Path $script:TempPath "reaplugs_x64.exe"
        $specs += @{
            Key         = 'ReaPlugs'
            DisplayName = 'ReaPlugs'
            OutFile     = $files.ReaPlugs
            Method      = 'IWR'
            Url         = 'https://www.reaper.fm/reaplugs/reaplugs236_x64-install.exe'
            BaseUrl     = $null
            UrlResolver = $null
            FallbackUrl = $null
            TimeoutSec  = 120
        }
    }

    if (-not $skipEAPO) {
        $files.EAPO = Join-Path $script:TempPath "EqualizerAPO64.exe"
        $specs += @{
            Key         = 'EAPO'
            DisplayName = 'Equalizer APO'
            OutFile     = $files.EAPO
            Method      = 'BITS'
            Url         = $null
            BaseUrl     = $null
            UrlResolver = $script:EapoUrlResolver
            FallbackUrl = 'https://cdn.artiswar.io/other-installers/EqualizerAPO-x64-1.4.2.exe'
            TimeoutSec  = 120
        }
    }

    if (-not $skipHeSuVi) {
        $files.HeSuVi = Join-Path $script:TempPath "HeSuVi.exe"
        $specs += @{
            Key         = 'HeSuVi'
            DisplayName = 'HeSuVi'
            OutFile     = $files.HeSuVi
            Method      = 'BITS'
            Url         = $null
            BaseUrl     = 'https://sourceforge.net/projects/hesuvi/files/HeSuVi_2.0.0.1.exe/download'
            UrlResolver = $null
            FallbackUrl = 'https://cdn.artiswar.io/other-installers/HeSuVi_2.0.0.1.exe'
            TimeoutSec  = 120
        }
    }

    # LEQ Control Panel (always download)
    $files.SoundControl = Join-Path $script:TempPath "LEQControlPanel.exe"
    $specs += @{
        Key         = 'SoundControl'
        DisplayName = 'LEQ Control Panel'
        OutFile     = $files.SoundControl
        Method      = 'IWR'
        Url         = $null
        BaseUrl     = $null
        UrlResolver = $script:LeqUrlResolver
        FallbackUrl = 'https://cdn.artiswar.io/LEQControlPanel.exe'
        TimeoutSec  = 600
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

# ============================================================================
# SECTION 4: Uninstall Functions
# ============================================================================


function Backup-ArtTuneLibrary {
    <#
    .SYNOPSIS
        Backs up the ArtTuneDB library folder before destructive operations.
    .OUTPUTS
        Backup folder path if successful, $null otherwise.
    #>
    $libraryPath = Join-Path $env:ProgramFiles "EqualizerAPO\config\ArtTuneDB\library"

    if (-not (Test-Path $libraryPath)) { return $null }

    $childItems = @(Get-ChildItem -Path $libraryPath -Recurse -File -ErrorAction SilentlyContinue)
    if ($childItems.Count -eq 0) { return $null }

    $docsFolder = [Environment]::GetFolderPath('MyDocuments')
    $timestamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $backupRoot = Join-Path $docsFolder "Art Tune Backups"
    $backupDest = Join-Path $backupRoot "library-$timestamp"

    Write-Host ""
    Write-Host "$($script:BoxMargin)Backing up ArtTuneDB library ($($childItems.Count) files)..." -ForegroundColor Cyan

    try {
        if (-not (Test-Path $backupRoot)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $libraryPath -Destination $backupDest -Recurse -Force
        Write-Host "$($script:BoxMargin)Library backed up to:" -ForegroundColor Green
        Write-Host "$($script:BoxMargin)$backupDest" -ForegroundColor DarkGray
        return $backupDest
    }
    catch {
        Write-Host "$($script:BoxMargin)Warning: Library backup failed: $_" -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)Continuing with uninstall..." -ForegroundColor Yellow
        return $null
    }
}

function Backup-EAPOConfig {
    <#
    .SYNOPSIS
        Backs up the entire E-APO config folder before destructive operations.
        Used when no ArtTuneDB library is detected (non-ArtTune E-APO user).
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

function Uninstall-ExistingEAPO {
    <#
    .SYNOPSIS
        Removes an existing Equalizer APO installation with backup.
    #>
    $eapoPath = Join-Path $env:ProgramFiles "EqualizerAPO"
    $eapoUninstall = Join-Path $eapoPath "Uninstall.exe"

    if (-not (Test-Path $eapoPath)) {
        Write-Host "$($script:BoxMargin)No existing E-APO detected, proceeding." -ForegroundColor DarkGray
        return $false
    }

    Write-Host "$($script:BoxMargin)Uninstalling E-APO..." -ForegroundColor Red

    # Kill LEQ Control Panel before device removal -- its COM audio callbacks
    # can crash if a third-party driver (e.g. Elgato) corrupts shared state
    # during audio subsystem destabilization (AccessViolationException).
    Stop-Process -Name "LEQControlPanel" -Force -ErrorAction SilentlyContinue
    Stop-EAPOEcosystemProcesses

    # Back up user data before destroying E-APO folder
    $libraryPath = Join-Path $eapoPath "config\ArtTuneDB\library"
    $libraryFiles = @(Get-ChildItem -Path $libraryPath -Recurse -File -ErrorAction SilentlyContinue)
    if ($libraryFiles.Count -gt 0) {
        $null = Backup-ArtTuneLibrary
    } else {
        $null = Backup-EAPOConfig
    }

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
        $null = Write-Wait -Message "Waiting for Audiosrv (retry)" -Until {
            $svc = Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
            $svc -and $svc.Status -eq 'Running'
        } -TimeoutSeconds 15
    }

    Write-Host "$($script:BoxMargin)E-APO uninstalled." -ForegroundColor Green
    return $true
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
        Where-Object { $_.Name -like "*Hi-Fi*" -or $_.Name -like "*HiFi*" }

    if (-not $hasRegEntry -and -not $hasDevice) {
        return $false
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
        $hifiFolders = @(
            "C:\Program Files (x86)\VB\ASIOBridge",
            "C:\Program Files\VB\CABLEHiFi",
            "C:\Program Files\VB\CABLE",
            "C:\Program Files (x86)\VB\CABLE"
        )
        foreach ($folder in $hifiFolders) {
            if (Test-Path $folder) { Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue }
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
                    Where-Object { $_.Name -match "VB:HiFi|Hi-Fi Cable|HiFiCable|VB:ASIOBridge|ASIO Bridge" } |
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
            $pnpRaw = & pnputil /enum-drivers 2>&1
            # Split into per-driver blocks (separated by blank lines).
            # Field names are localized, but oem*.inf and product strings are not.
            $blockText = ""
            foreach ($line in $pnpRaw) {
                $trimmed = "$line".Trim()
                if ($trimmed -eq '' -and $blockText.Length -gt 0) {
                    if ($blockText -match '(oem\d+\.inf)') {
                        $oemInf = $Matches[1]
                        if ($blockText -match 'VB-Audio' -and
                            $blockText -match '(?i)hifi|hi-fi|hfvaio|hfcable') {
                            & pnputil /delete-driver $oemInf /force 2>&1 | Out-Null
                        }
                    }
                    $blockText = ""
                    continue
                }
                $blockText += " $trimmed"
            }
            # Handle last block (no trailing blank line)
            if ($blockText.Length -gt 0 -and
                $blockText -match '(oem\d+\.inf)') {
                $oemInf = $Matches[1]
                if ($blockText -match 'VB-Audio' -and
                    $blockText -match '(?i)hifi|hi-fi|hfvaio|hfcable') {
                    & pnputil /delete-driver $oemInf /force 2>&1 | Out-Null
                }
            }
        } catch { } # Best-effort; pnputil errors are non-fatal
        $true
    } -TimeoutSeconds 15 | Out-Null

    # -- Nuclear cleanup: remove phantom/ghost Hi-Fi Cable devices --
    Write-Wait -Message "Removing phantom Hi-Fi Cable devices..." -Until {
        try {
            $hifiDevices = Get-PnpDevice -ErrorAction SilentlyContinue |
                Where-Object {
                    ($_.Status -eq 'Error' -or $_.Status -eq 'Unknown') -and
                    ($_.FriendlyName -match 'Hi-?Fi' -or $_.FriendlyName -match 'HiFi') -and
                    $_.FriendlyName -notmatch 'Voicemeeter'
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
    $vmExe = Join-Path "${env:ProgramFiles(x86)}" "VB\Voicemeeter\voicemeeter.exe"
    if (-not (Test-Path $vmExe)) {
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

    Write-Host "$($script:BoxMargin)Hi-Fi Cable uninstalled." -ForegroundColor Green
    return $true
}

function Uninstall-ExistingVoicemeeter {
    <#
    .SYNOPSIS
        Removes Voicemeeter, its drivers, auto-start entries, and user data.
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
        return $false
    }

    Write-Host "$($script:BoxMargin)Uninstalling Voicemeeter..." -ForegroundColor Red

    # Detect variant and select correct uninstaller
    $hasPotato = Test-Path (Join-Path $vmFolder "voicemeeter8.exe")
    $hasBanana = Test-Path (Join-Path $vmFolder "voicemeeterpro.exe")

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
                    Where-Object { $_.Name -match "VB:Voicemeeter|Voicemeeter" } |
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
    return $true
}

function Invoke-FreshStart {
    <#
    .SYNOPSIS
        Uninstalls all audio components in order.
    .PARAMETER PromptRestart
        If true, prompts user to restart after uninstalling (default: true).
    .OUTPUTS
        Array of component names that were actually removed.
    #>
    param(
        [bool]$PromptRestart = $true
    )

    Write-Host ""
    Write-Host "$($script:BoxMargin)Running Fresh Start..." -ForegroundColor Red

    # Kill LEQ Control Panel before device removal -- its COM audio callbacks
    # can crash if a third-party driver (e.g. Elgato) corrupts shared state
    # during audio subsystem destabilization (AccessViolationException).
    Stop-Process -Name "LEQControlPanel" -Force -ErrorAction SilentlyContinue
    Stop-EAPOEcosystemProcesses

    # Detect what's installed before doing anything
    $hasEapo = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO")
    $hasHifi = ($script:HiFiCableRegistryKeys | Where-Object { Test-Path $_ } | Select-Object -First 1) -or
        (Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Hi-Fi*" -or $_.Name -like "*HiFi*" })
    $hasVm = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VB:Voicemeeter {17359A74-1236-5467}",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\VB:Voicemeeter {17359A74-1236-5467}"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $hasEapo -and -not $hasHifi -and -not $hasVm) {
        Write-Host "$($script:BoxMargin)No existing installations detected, proceeding." -ForegroundColor DarkGray
        return @()
    }

    Write-Host ""

    $removed = @()
    if (Uninstall-ExistingEAPO) { $removed += "E-APO + HeSuVi" }
    if (Uninstall-ExistingHiFiCable) { $removed += "Hi-Fi Cable" }
    if (Uninstall-ExistingVoicemeeter) { $removed += "Voicemeeter" }

    if ($removed.Count -gt 0) {
        if ($PromptRestart) {
            Write-Host ""
            Write-Host "$($script:BoxMargin)Removed: $($removed -join ', ')" -ForegroundColor Green
            Write-Host ""
            Write-Host "$($script:BoxMargin)A restart is required to finish removing drivers." -ForegroundColor Yellow
            Write-Host "$($script:BoxMargin)After restarting, press UP ARROW in PowerShell to re-run this script." -ForegroundColor Yellow
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

    return $removed
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

function Install-HiFiCable {
    <#
    .SYNOPSIS
        Extracts and installs the Hi-Fi Cable virtual audio driver from a ZIP archive.
    #>
    param([ValidateNotNullOrEmpty()][string]$ZipPath)

    Write-Host "$($script:BoxMargin)Installing Hi-Fi Cable..." -ForegroundColor Cyan

    # Check if already installed
    $existing = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*Hi-Fi*" -or $_.Name -like "*HiFi*" }
    if ($existing) {
        Write-Host "$($script:BoxMargin)Hi-Fi Cable already installed." -ForegroundColor Green
        return $true
    }

    # Extract ZIP
    $extractPath = Join-Path $script:TempPath "HiFiCable_Extract"
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force

    # Find setup exe
    $setupExe = Get-ChildItem -LiteralPath $extractPath -Filter "HiFiCableAsioBridgeSetup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $setupExe) {
        $setupExe = Get-ChildItem -LiteralPath $extractPath -Filter "*Setup*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $setupExe) {
        Write-Host "$($script:BoxMargin)ERROR: Hi-Fi Cable setup exe not found in archive." -ForegroundColor Red
        return $false
    }

    # Pre-trust VB-Audio driver certificate (suppresses driver confirmation dialog)
    $null = Install-VBAudioCertificate

    # Run silent install
    $proc = Start-Process -FilePath $setupExe.FullName -ArgumentList "-i -h" -PassThru -ErrorAction Stop
    Write-Wait -Message "Installing Hi-Fi Cable driver..." -Until { $proc.HasExited } -TimeoutSeconds 60 | Out-Null
    Start-Sleep -Seconds 2

    # Cleanup extract folder
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "$($script:BoxMargin)Hi-Fi Cable installed." -ForegroundColor Green
    return $true
}

function Install-Voicemeeter {
    <#
    .SYNOPSIS
        Extracts and installs Voicemeeter Standard from a ZIP archive.
    #>
    param([ValidateNotNullOrEmpty()][string]$ZipPath)

    Write-Host "$($script:BoxMargin)Installing Voicemeeter..." -ForegroundColor Cyan

    $verifyPath = Join-Path ${env:ProgramFiles(x86)} "VB\Voicemeeter\voicemeeter.exe"
    if (Test-Path -LiteralPath $verifyPath) {
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

    # Verify
    if (-not (Test-Path -LiteralPath $verifyPath)) {
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

function Install-Eapo {
    <#
    .SYNOPSIS
        Installs Equalizer APO and creates the ArtTuneDB folder structure.
    #>
    param([ValidateNotNullOrEmpty()][string]$InstallerPath)

    Write-Host "$($script:BoxMargin)Installing Equalizer APO..." -ForegroundColor Cyan

    $eapoConfig = Join-Path $env:ProgramFiles "EqualizerAPO\config"
    $alreadyInstalled = Test-Path $eapoConfig

    if ($alreadyInstalled) {
        Write-Host "$($script:BoxMargin)Equalizer APO already installed." -ForegroundColor Green
    } else {
        Unblock-File -LiteralPath $InstallerPath -ErrorAction SilentlyContinue
        # Launch installer -- /S is semi-silent (Device Selector dialog still appears)
        # /D sets explicit install dir (matches ATK app: InstallEapoFromFileAsync)
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList "/S /D=$env:ProgramFiles\EqualizerAPO" -PassThru -ErrorAction Stop

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

        # Verify
        if (-not (Test-Path $eapoConfig)) {
            Write-Host "$($script:BoxMargin)WARNING: Equalizer APO verification failed." -ForegroundColor Yellow
            return $false
        }

        Write-Host "$($script:BoxMargin)Equalizer APO installed." -ForegroundColor Green
    } # end else (fresh E-APO install)

    # Create desktop shortcuts
    $desktopPath = [Environment]::GetFolderPath('Desktop')

    # ArtTuneDB folder inside E-APO config
    $artTuneDBDir = Join-Path $eapoConfig "ArtTuneDB"
    $artTuneDBLibrary = Join-Path $artTuneDBDir "library"
    try {
        New-Item -Path $artTuneDBLibrary -ItemType Directory -Force | Out-Null
        $readmeContent = @"
ArtTuneDB
=======

ArtIsWar.url                    - artiswar.io
ArtTuneDB.url                   - ArtTuneDB GitHub (library downloads and uninstall script)
E-APO Configuration Editor.lnk  - Equalizer APO Configuration Editor
LEQ Control Panel.lnk           - Loudness EQ control panel
library\                         - Game EQ profiles and presets

Extract ArtTuneDB library releases into the library\ folder.
Download: https://github.com/ArtIsWar/ArtTuneDB/releases
"@
        Set-Content -Path (Join-Path $artTuneDBDir "README.txt") -Value $readmeContent
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
        if (Test-Path $outRef) {
            $sz = (Get-Item $outRef -ErrorAction SilentlyContinue).Length
            if ($sz -ge 1MB) { "[{0:N1} MB]" -f ($sz / 1MB) }
            elseif ($sz -ge 1KB) { "[{0:N0} KB]" -f ($sz / 1KB) }
        }
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
        Downloads the ArtTune HRIR files (48 kHz and 44.1 kHz) into the HeSuVi hrir directory.
    #>

    $hrirDir    = Join-Path $env:ProgramFiles "EqualizerAPO\config\HeSuVi\hrir"
    $hrirFile   = Join-Path $hrirDir "EAC_Default.wav"
    $hrir44Dir  = Join-Path $hrirDir "44"
    $hrir44File = Join-Path $hrir44Dir "EAC_Default.wav"

    if ((Test-Path $hrirFile) -and (Test-Path $hrir44File)) {
        Write-Host "$($script:BoxMargin)ArtTune HRIR already installed." -ForegroundColor Green
        return $true
    }

    Write-Host "$($script:BoxMargin)Installing ArtTune HRIR..." -ForegroundColor Cyan

    if (-not (Test-Path $hrirDir)) {
        New-Item -ItemType Directory -Path $hrirDir -Force | Out-Null
    }
    if (-not (Test-Path $hrir44Dir)) {
        New-Item -ItemType Directory -Path $hrir44Dir -Force | Out-Null
    }

    $size48 = Get-HrirFile -Url "https://cdn.artiswar.io/HeSuVi/hrir/EAC_Default.wav" -Label "ArtTune HRIR (48 kHz)" -Destination $hrirFile
    if (-not $size48) { return $false }

    $size44 = Get-HrirFile -Url "https://cdn.artiswar.io/HeSuVi/hrir/44/EAC_Default.wav" -Label "ArtTune HRIR (44.1 kHz)" -Destination $hrir44File
    if (-not $size44) { return $false }

    Write-Host "$($script:BoxMargin)ArtTune HRIR installed (48 kHz: $([math]::Round($size48 / 1KB)) KB, 44.1 kHz: $([math]::Round($size44 / 1KB)) KB)." -ForegroundColor Green
    return $true
}

function Write-InitialConfig {
    <#
    .SYNOPSIS
        Writes the starter config.txt to the E-APO config folder.
        Always overwrites to ensure correct line order.
    #>

    $configFile = Join-Path $env:ProgramFiles "EqualizerAPO\config\config.txt"

    try {
        $lines = @(
            "# Choose the Pre file from the Game > Season folder in ArtTuneDB"
            "# PRE HESUVI"
            "Include: ArtTuneDB\library\"
            "# "
            "# DO NOT REMOVE HESUVI #"
            "Include: HeSuVi\hesuvi.txt"
            "# "
            "# Use the squiglink link and Game/Season target EQ to generate an EQ for your headset+game"
            "Include: ArtTuneDB\library\"
            "# "
            "# Choose the Post file from the Game > Season folder in ArtTuneDB"
            "# POST HESUVI"
            "Include: ArtTuneDB\library\"
        )
        Set-Content -Path $configFile -Value ($lines -join "`r`n") -Force
        Write-Host "$($script:BoxMargin)config.txt written with starter template." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "$($script:BoxMargin)WARNING: Could not write config.txt: $_" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================================
# SECTION 6: Endpoint Rename
# ============================================================================

function Rename-AudioEndpoints {
    <#
    .SYNOPSIS
        Renames Hi-Fi Cable and Voicemeeter endpoints via .reg import.
    #>
    Write-Host "$($script:BoxMargin)Renaming audio endpoints..." -ForegroundColor Cyan

    $MMDEVICES_RENDER = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    $MMDEVICES_CAPTURE = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
    $PROP_NAME = "{a45c254e-df1c-4efd-8020-67d146a850e0},2"
    $PROP_DESC = "{b3f8fa53-0004-438e-9003-51a46e139bfc},6"

    $renames = @()
    $alreadyCorrect = 0

    # Scan both Render and Capture trees
    $trees = @(
        @{ Path = $MMDEVICES_RENDER; Type = 'Render' },
        @{ Path = $MMDEVICES_CAPTURE; Type = 'Capture' }
    )

    foreach ($tree in $trees) {
        if (-not (Test-Path $tree.Path)) { continue }

        foreach ($deviceKey in Get-ChildItem -Path $tree.Path -ErrorAction SilentlyContinue) {
            $guid = $deviceKey.PSChildName
            $deviceState = (Get-ItemProperty -Path $deviceKey.PSPath -Name "DeviceState" -ErrorAction SilentlyContinue).DeviceState
            if ($deviceState -ne 1) { continue }  # Only active devices

            $propsPath = Join-Path $deviceKey.PSPath "Properties"
            if (-not (Test-Path $propsPath)) { continue }

            try {
                $props = Get-ItemProperty -Path $propsPath -ErrorAction SilentlyContinue
                $name = $props.$PROP_NAME
                $desc = $props.$PROP_DESC

                # Hi-Fi Cable matching (render + capture)
                if ($name -like '*Hi-Fi*' -or $name -like '*HiFi*' -or $name -eq 'Art Tune' -or
                    $desc -eq 'VB-Audio Hi-Fi Cable' -or $desc -eq 'VB-Audio Virtual Cable') {

                    if ($name -eq 'Art Tune') {
                        $alreadyCorrect++
                    } else {
                        $renames += @{ GUID = $guid; NewName = 'Art Tune'; Type = $tree.Type; OldName = $name }
                    }
                }
                # Voicemeeter Input matching (render only -- it's a playback endpoint)
                elseif ($tree.Type -eq 'Render' -and ($name -eq 'Voicemeeter Input' -or $name -eq 'VoiceMeeter Input' -or $name -eq 'Normal Audio')) {
                    if ($name -eq 'Normal Audio') {
                        $alreadyCorrect++
                    } else {
                        $renames += @{ GUID = $guid; NewName = 'Normal Audio'; Type = $tree.Type; OldName = $name }
                    }
                }
                # Voicemeeter Out B1 matching (capture only -- it's a recording endpoint)
                elseif ($tree.Type -eq 'Capture' -and ($name -eq 'Voicemeeter Out B1' -or $name -like '*VoiceMeeter Output*' -or $name -eq 'Virtual Mix')) {
                    if ($name -eq 'Virtual Mix') {
                        $alreadyCorrect++
                    } else {
                        $renames += @{ GUID = $guid; NewName = 'Virtual Mix'; Type = $tree.Type; OldName = $name }
                    }
                }
            } catch { } # Some devices may lack expected properties; skip gracefully
        }
    }

    if ($alreadyCorrect -gt 0) {
        Write-Host "$($script:BoxMargin)$alreadyCorrect endpoint(s) already renamed." -ForegroundColor DarkGray
    }

    if ($renames.Count -eq 0) {
        if ($alreadyCorrect -gt 0) {
            Write-Host "$($script:BoxMargin)All endpoints already correct." -ForegroundColor Green
        } else {
            Write-Host "$($script:BoxMargin)No endpoints found to rename." -ForegroundColor Yellow
        }
        return $true
    }

    # Build .reg file
    $regContent = "Windows Registry Editor Version 5.00`r`n"
    foreach ($rename in $renames) {
        $regPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$($rename.Type)\$($rename.GUID)\Properties"
        $regContent += "`r`n[$regPath]`r`n"
        $regContent += "`"{a45c254e-df1c-4efd-8020-67d146a850e0},2`"=`"$($rename.NewName)`"`r`n"
    }

    # Write and import .reg
    if (-not (Test-Path $script:TempPath)) {
        New-Item -ItemType Directory -Path $script:TempPath -Force | Out-Null
    }
    $regFile = Join-Path $script:TempPath "rename.reg"
    $regContent | Out-File -FilePath $regFile -Encoding ASCII -Force

    $regProc = Start-Process -FilePath "regedit.exe" -ArgumentList "/s `"$regFile`"" -Wait -PassThru -WindowStyle Hidden
    if ($regProc.ExitCode -ne 0) {
        Write-Host "$($script:BoxMargin)[!] Registry import returned exit code $($regProc.ExitCode)" -ForegroundColor Yellow
    }
    Start-Sleep -Milliseconds 200

    # Verify renames
    $verified = $true
    foreach ($rename in $renames) {
        $propsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$($rename.Type)\$($rename.GUID)\Properties"
        try {
            $actualName = (Get-ItemProperty -LiteralPath $propsPath -Name $PROP_NAME -ErrorAction Stop).$PROP_NAME
            if ($actualName -eq $rename.NewName) {
                Write-Host "$($script:BoxMargin)$($rename.OldName) -> $($rename.NewName)" -ForegroundColor Green
            } else {
                Write-Host "$($script:BoxMargin)WARNING: '$($rename.OldName)' rename failed (got '$actualName')" -ForegroundColor Yellow
                $verified = $false
            }
        } catch {
            Write-Host "$($script:BoxMargin)WARNING: Could not verify rename for $($rename.GUID)" -ForegroundColor Yellow
            $verified = $false
        }
    }

    # Cleanup
    Remove-Item $regFile -Force -ErrorAction SilentlyContinue

    # Audio service restart to apply renames
    Restart-AudioServices

    if ($verified) {
        Write-Host "$($script:BoxMargin)All endpoints renamed successfully." -ForegroundColor Green
    }
    return $verified
}

# ============================================================================
# SECTION 7: Creative App + LEQ Control Panel Placement
# ============================================================================

function Install-CreativeApp {
    <#
    .SYNOPSIS
        Installs the Creative App for Sound Blaster device management.
        Tries winget first, falls back to direct CDN download.
    #>
    Write-Host "$($script:BoxMargin)Installing Creative App..." -ForegroundColor Cyan

    # Detection: check common install paths
    $paths = @(
        "$env:ProgramFiles\Creative\Creative App",
        "${env:ProgramFiles(x86)}\Creative\Creative App"
    )
    $installed = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($installed) {
        Write-Host "$($script:BoxMargin)Creative App already installed." -ForegroundColor Green
        return $true
    }

    # Kill existing processes before install
    foreach ($name in @("Creative.App", "CreativeApp")) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "$($script:BoxMargin)Stopping $($_.ProcessName)..." -ForegroundColor DarkGray
            $_.Kill()
            $_.WaitForExit(3000)
        }
    }

    # -- Tier 1: Try winget ------------------------------------------------
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $proc = Start-Process -FilePath "winget" `
                -ArgumentList 'install --id "CreativeTechnology.CreativeApp" --silent --accept-package-agreements --accept-source-agreements' `
                -PassThru -WindowStyle Hidden -ErrorAction Stop

            Write-Wait -Message "Installing Creative App via winget..." -Until { $proc.HasExited } -TimeoutSeconds 300 | Out-Null

            if ($proc.HasExited -and $proc.ExitCode -eq 0) {
                Write-Host "$($script:BoxMargin)Creative App installed." -ForegroundColor Green
                return $true
            }

            if (-not $proc.HasExited) {
                try { $proc.Kill() } catch { }
                Write-Host "$($script:BoxMargin)winget install timed out, trying direct download..." -ForegroundColor Yellow
            } else {
                Write-Host "$($script:BoxMargin)winget install failed (exit code $($proc.ExitCode)), trying direct download..." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "$($script:BoxMargin)winget install failed, trying direct download..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "$($script:BoxMargin)winget not available, trying direct download..." -ForegroundColor DarkGray
    }

    # -- Tier 2: Direct download from Creative CDN -------------------------
    $cdnUrl = "https://files.creative.com/creative/bin/apps/swureleases/win/creativeapp/release/CreativeAppSetup_1.24.00.00.exe"
    $setupPath = Join-Path $script:TempPath "CreativeAppSetup.exe"

    try {
        Invoke-WebRequest -Uri $cdnUrl -OutFile $setupPath -UseBasicParsing

        Unblock-File -LiteralPath $setupPath -ErrorAction SilentlyContinue
        $proc = Start-Process -FilePath $setupPath -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -PassThru -ErrorAction Stop

        Write-Wait -Message "Installing Creative App..." -Until { $proc.HasExited } -TimeoutSeconds 300 | Out-Null

        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch { }
            Write-Host "$($script:BoxMargin)WARNING: Creative App install timed out." -ForegroundColor Yellow
            return $false
        }

        if ($proc.ExitCode -ne 0) {
            Write-Host "$($script:BoxMargin)WARNING: Creative App install returned exit code $($proc.ExitCode)." -ForegroundColor Yellow
            return $false
        }

        # Verify
        $installed = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($installed) {
            Write-Host "$($script:BoxMargin)Creative App installed." -ForegroundColor Green
            return $true
        }

        Write-Host "$($script:BoxMargin)WARNING: Creative App installer completed but app not detected." -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "$($script:BoxMargin)WARNING: Creative App download failed." -ForegroundColor Yellow
        Write-Host "$($script:BoxMargin)Opening Creative support page for manual install..." -ForegroundColor DarkGray
        Start-Process 'https://support.creative.com/Products/ProductDetails.aspx?prodID=23705'
        return $false
    }
    finally {
        Remove-Item $setupPath -Force -ErrorAction SilentlyContinue
    }
}

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

    # Prerequisites
    Install-Winget

    # Audio warning
    $null = Write-CenteredBlock @(@{ Text = "$([char]0x26A0) WARNING"; Color = 'Red' })
    $null = Write-CenteredBlock @(
        @{ Text = 'This installer will temporarily kill audio on this PC.'; Color = 'Red' }
        @{ Text = 'Watch the video guide on your phone or a different device.'; Color = 'Red' }
        @{ Text = 'Close all apps and save your work before continuing.'; Color = 'Red' }
    )

    # Outer loop allows device sub-menu [b] to return to main menu
    :mainMenu while ($true) {

    # Main menu with [d] submenu under option 2
    Write-Host ""
    $menuItems = @(
        @{ Text = 'What would you like to do?'; Color = 'Yellow' }
        @{ Text = ''; Color = 'White' }
        @{ Text = '[1] Install - Voicemeeter Setup (USB headphones, DAC, onboard audio)'; Color = 'White' }
        @{ Text = '[2] Install - Art Tune Approved Device'; Color = 'White' }
        @{ Text = '[3] Uninstall everything'; Color = 'White' }
        @{ Text = '[t] Thank you - Credits & developer links'; Color = 'White' }
        @{ Text = '[b] artiswar.io - Something easier coming soon...'; Color = 'DarkGray' }
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
            Start-Process "https://artiswar.io/arttunekit.html"
            Write-Host "$($script:BoxMargin)Opened in browser." -ForegroundColor Green
            continue mainMenu
        }
        $num = 0
        if ([int]::TryParse($selection, [ref]$num) -and $num -ge 1 -and $num -le 3) {
            $hwChoice = $num
            break
        }
        Write-Host "$($script:BoxMargin)Invalid choice. Enter 1, 2, 3, b, or t." -ForegroundColor Red
    }

    if ($hwChoice -eq 3) {
        # ===============================================================
        # PATH C: UNINSTALL
        # ===============================================================
        $removed = Invoke-FreshStart -PromptRestart $false

        # Remove ArtTuneDB desktop shortcut
        $artTuneDBLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "ArtTuneDB.lnk"
        if (Test-Path $artTuneDBLnk) { Remove-Item $artTuneDBLnk -Force -ErrorAction SilentlyContinue }

        # Optional LEQ Control Panel removal
        Write-Host ""
        Write-Host "$($script:BoxMargin)Also remove LEQ Control Panel? [Y/n]: " -ForegroundColor Yellow -NoNewline
        $removeScp = Read-Host
        if ($removeScp -ne 'n' -and $removeScp -ne 'N') {
            if (Uninstall-SoundControl) { $removed += "LEQ Control Panel" }
        }

        Write-UninstallCompletion -RemovedComponents $removed

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

    } elseif ($hwChoice -eq 2) {
        # ===============================================================
        # PATH A: APPROVED DEVICE
        # ===============================================================

        # Device sub-menu
        Write-Host ""
        $devMenuItems = @(
            @{ Text = 'Which device?'; Color = 'Yellow' }
            @{ Text = ''; Color = 'White' }
            @{ Text = '[1] Sound Blaster GC7 / G8'; Color = 'White' }
            @{ Text = '[m] Back to main menu'; Color = 'DarkGray' }
        )
        $devMargin = Write-CenteredBlock $devMenuItems
        Write-Host ""

        $deviceChoice = $null
        while ($true) {
            Write-Host "$devMargin" -NoNewline
            Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
            $devSelection = Read-Host
            if ($devSelection -eq 'm' -or $devSelection -eq 'M') {
                continue mainMenu
            }
            if ($devSelection -eq '1') {
                $deviceChoice = 'soundblaster'
                break
            }
            Write-Host "$($script:BoxMargin)Invalid choice. Enter 1 or m." -ForegroundColor Red
        }

        Write-Host ""
        $modeMenuItems = @(
            @{ Text = 'Installation mode:'; Color = 'Yellow' }
            @{ Text = ''; Color = 'White' }
            @{ Text = '[1] Fresh Start (Recommended) - uninstall existing E-APO first'; Color = 'White' }
            @{ Text = '[2] Advanced - keep what''s already installed'; Color = 'White' }
            @{ Text = '[m] Back to main menu'; Color = 'DarkGray' }
        )
        $modeMargin = Write-CenteredBlock $modeMenuItems
        Write-Host ""

        while ($true) {
            Write-Host "$modeMargin" -NoNewline
            Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
            $modeSelection = Read-Host
            if ($modeSelection -eq 'm' -or $modeSelection -eq 'M') { continue mainMenu }
            $modeNum = 0
            if ([int]::TryParse($modeSelection, [ref]$modeNum) -and $modeNum -ge 1 -and $modeNum -le 2) {
                $modeChoice = $modeNum
                break
            }
            Write-Host "$($script:BoxMargin)Invalid choice. Enter 1, 2, or m." -ForegroundColor Red
        }

        if ($modeChoice -eq 1) {
            $eapoWasInstalled = Test-Path (Join-Path $env:ProgramFiles "EqualizerAPO")
            $null = Uninstall-ExistingEAPO

            if ($eapoWasInstalled) {
                Write-Host ""
                Write-Host "$($script:BoxMargin)A restart is required to finish removing E-APO drivers." -ForegroundColor Yellow
                Write-Host "$($script:BoxMargin)After restarting, press UP ARROW in PowerShell to re-run this script." -ForegroundColor Yellow
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

        Write-Host ""
        :dlRetryA while ($true) {
            try {
                $files = Get-Downloads
                break dlRetryA
            } catch {
                Write-Host ""
                Write-Host "$($script:BoxMargin)Download failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                :dlMenuA while ($true) {
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
                        'r' { break dlMenuA }
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

        # Determine step count based on device
        $totalSteps = if ($deviceChoice -eq 'soundblaster') { 6 } else { 5 }
        $step = 0

        Write-Host ""
        $step++; Write-Host "$($script:BoxMargin)Installing [$step/$totalSteps]..." -ForegroundColor Yellow
        if ($files.ReaPlugs) { $null = Install-ReaPlugs -InstallerPath $files.ReaPlugs }
        $step++; Write-Host "$($script:BoxMargin)Installing [$step/$totalSteps]..." -ForegroundColor Yellow
        if ($files.EAPO) { $null = Install-Eapo -InstallerPath $files.EAPO }
        $step++; Write-Host "$($script:BoxMargin)Installing [$step/$totalSteps]..." -ForegroundColor Yellow
        if ($files.HeSuVi) { $null = Install-HeSuVi -InstallerPath $files.HeSuVi }
        $step++; Write-Host "$($script:BoxMargin)Installing [$step/$totalSteps]..." -ForegroundColor Yellow
        $null = Install-ArtTuneHRIR
        $null = Write-InitialConfig

        if ($deviceChoice -eq 'soundblaster') {
            $step++; Write-Host "$($script:BoxMargin)Installing [$step/$totalSteps]..." -ForegroundColor Yellow
            $null = Install-CreativeApp
        }

        $step++; Write-Host "$($script:BoxMargin)Installing [$step/$totalSteps]..." -ForegroundColor Yellow
        if ($files.SoundControl) {
            $null = Install-SoundControl -SourcePath $files.SoundControl
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

        $scInstalled = [bool]$files.SoundControl
        if ($deviceChoice -eq 'soundblaster') {
            $result = Write-DeviceCompletion -IncludeCreativeApp -SoundControlInstalled $scInstalled
        } else {
            $result = Write-DeviceCompletion -SoundControlInstalled $scInstalled
        }

        # Cleanup
        Remove-Item $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue

        if ($result -eq 'mainMenu') { continue mainMenu }
        if ($result -eq 'quit') { break mainMenu }

    } else {
        # ===============================================================
        # PATH B: DAC / AMP / ONBOARD
        # ===============================================================
        Write-Host ""
        $modeMenuItems = @(
            @{ Text = 'Installation mode:'; Color = 'Yellow' }
            @{ Text = ''; Color = 'White' }
            @{ Text = '[1] Fresh Start (Recommended) - uninstall existing audio tools first'; Color = 'White' }
            @{ Text = '[2] Advanced - keep what''s already installed'; Color = 'White' }
            @{ Text = '[m] Back to main menu'; Color = 'DarkGray' }
        )
        $modeMargin = Write-CenteredBlock $modeMenuItems
        Write-Host ""

        while ($true) {
            Write-Host "$modeMargin" -NoNewline
            Write-Host "Choice: " -ForegroundColor Yellow -NoNewline
            $modeSelection = Read-Host
            if ($modeSelection -eq 'm' -or $modeSelection -eq 'M') { continue mainMenu }
            $modeNum = 0
            if ([int]::TryParse($modeSelection, [ref]$modeNum) -and $modeNum -ge 1 -and $modeNum -le 2) {
                $modeChoice = $modeNum
                break
            }
            Write-Host "$($script:BoxMargin)Invalid choice. Enter 1, 2, or m." -ForegroundColor Red
        }

        if ($modeChoice -eq 1) {
            $null = Invoke-FreshStart
        }

        Write-Host ""
        :dlRetryB while ($true) {
            try {
                $files = Get-Downloads -IncludeVirtualAudio
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

        Write-Host ""
        Write-Host "$($script:BoxMargin)Installing [1/8]..." -ForegroundColor Yellow
        if ($files.HiFiCable) { $null = Install-HiFiCable -ZipPath $files.HiFiCable }
        Write-Host "$($script:BoxMargin)Installing [2/8]..." -ForegroundColor Yellow
        if ($files.Voicemeeter) { $null = Install-Voicemeeter -ZipPath $files.Voicemeeter }
        Write-Host "$($script:BoxMargin)Installing [3/8]..." -ForegroundColor Yellow
        if ($files.ReaPlugs) { $null = Install-ReaPlugs -InstallerPath $files.ReaPlugs }

        # Rename-AudioEndpoints restarts audio services internally after reg import
        Write-Host "$($script:BoxMargin)Installing [4/8]..." -ForegroundColor Yellow
        $null = Rename-AudioEndpoints

        Write-Host "$($script:BoxMargin)Installing [5/8]..." -ForegroundColor Yellow
        if ($files.EAPO) { $null = Install-Eapo -InstallerPath $files.EAPO }
        Write-Host "$($script:BoxMargin)Installing [6/8]..." -ForegroundColor Yellow
        if ($files.HeSuVi) { $null = Install-HeSuVi -InstallerPath $files.HeSuVi }
        Write-Host "$($script:BoxMargin)Installing [7/8]..." -ForegroundColor Yellow
        $null = Install-ArtTuneHRIR
        $null = Write-InitialConfig
        Write-Host "$($script:BoxMargin)Installing [8/8]..." -ForegroundColor Yellow
        if ($files.SoundControl) {
            $null = Install-SoundControl -SourcePath $files.SoundControl
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

        $result = Write-Completion -SoundControlInstalled ([bool]$files.SoundControl)

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
}


# SIG # Begin signature block
# MIIsZwYJKoZIhvcNAQcCoIIsWDCCLFQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBfsTxHGYhRyJpH
# +u5BmgAKw9y++9XWGIwYME8Ait078qCCJXYwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggWNMIIEdaADAgECAhAOmxiO
# +dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAi
# BgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAw
# MDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERp
# Z2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsb
# hA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iT
# cMKyunWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGb
# NOsFxl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclP
# XuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCr
# VYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFP
# ObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTv
# kpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWM
# cCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls
# 5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBR
# a2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6
# MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qY
# rhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8E
# BAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5k
# aWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDig
# NoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCg
# v0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQT
# SnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh
# 65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSw
# uKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAO
# QGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjD
# TZ9ztwGpn1eqXijiuZQwggYcMIIEBKADAgECAhAz1wiokUBTGeKlu9M5ua1uMA0G
# CSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExp
# bWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290
# IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFcxCzAJBgNVBAYT
# AkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28g
# UHVibGljIENvZGUgU2lnbmluZyBDQSBFViBSMzYwggGiMA0GCSqGSIb3DQEBAQUA
# A4IBjwAwggGKAoIBgQC70f4et0JbePWQp64sg/GNIdMwhoV739PN2RZLrIXFuwHP
# 4owoEXIEdiyBxasSekBKxRDogRQ5G19PB/YwMDB/NSXlwHM9QAmU6Kj46zkLVdW2
# DIseJ/jePiLBv+9l7nPuZd0o3bsffZsyf7eZVReqskmoPBBqOsMhspmoQ9c7gqgZ
# YbU+alpduLyeE9AKnvVbj2k4aOqlH1vKI+4L7bzQHkNDbrBTjMJzKkQxbr6PuMYC
# 9ruCBBV5DFIg6JgncWHvL+T4AvszWbX0w1Xn3/YIIq620QlZ7AGfc4m3Q0/V8tm9
# VlkJ3bcX9sR0gLqHRqwG29sEDdVOuu6MCTQZlRvmcBMEJd+PuNeEM4xspgzraLqV
# T3xE6NRpjSV5wyHxNXf4T7YSVZXQVugYAtXueciGoWnxG06UE2oHYvDQa5mll1Ce
# HDOhHu5hiwVoHI717iaQg9b+cYWnmvINFD42tRKtd3V6zOdGNmqQU8vGlHHeBzoh
# +dYyZ+CcblSGoGSgg8sCAwEAAaOCAWMwggFfMB8GA1UdIwQYMBaAFDLrkpr/NZZI
# LyhAQnAgNpFcF4XmMB0GA1UdDgQWBBSBMpJBKyjNRsjEosYqORLsSKk/FDAOBgNV
# HQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEF
# BQcDAzAaBgNVHSAEEzARMAYGBFUdIAAwBwYFZ4EMAQMwSwYDVR0fBEQwQjBAoD6g
# PIY6aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25p
# bmdSb290UjQ2LmNybDB7BggrBgEFBQcBAQRvMG0wRgYIKwYBBQUHMAKGOmh0dHA6
# Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0
# Ni5wN2MwIwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqG
# SIb3DQEBDAUAA4ICAQBfNqz7+fZyWhS38Asd3tj9lwHS/QHumS2G6Pa38Dn/1oFK
# WqdCSgotFZ3mlP3FaUqy10vxFhJM9r6QZmWLLXTUqwj3ahEDCHd8vmnhsNufJIkD
# 1t5cpOCy1rTP4zjVuW3MJ9bOZBHoEHJ20/ng6SyJ6UnTs5eWBgrh9grIQZqRXYHY
# NneYyoBBl6j4kT9jn6rNVFRLgOr1F2bTlHH9nv1HMePpGoYd074g0j+xUl+yk72M
# lQmYco+VAfSYQ6VK+xQmqp02v3Kw/Ny9hA3s7TSoXpUrOBZjBXXZ9jEuFWvilLIq
# 0nQ1tZiao/74Ky+2F0snbFrmuXZe2obdq2TWauqDGIgbMYL1iLOUJcAhLwhpAuNM
# u0wqETDrgXkG4UGVKtQg9guT5Hx2DJ0dJmtfhAH2KpnNr97H8OQYok6bLyoMZqaS
# dSa+2UA1E2+upjcaeuitHFFjBypWBmztfhj24+xkc6ZtCDaLrw+ZrnVrFyvCTWrD
# UUZBVumPwo3/E3Gb2u2e05+r5UWmEsUUWlJBl6MGAAjF5hzqJ4I8O9vmRsTvLQA1
# E802fZ3lqicIBczOwDYOSxlP0GOabb/FKVMxItt1UHeG0PL4au5rBhs+hSMrl8h+
# eplBDN1Yfw6owxI9OjWb4J0sjBeBVESoeh2YnZZ/WVimVGX/UUIL+Efrz/jlvzCC
# BqUwggUNoAMCAQICEFOGK0nCUn5DxL7vamlI8k0wDQYJKoZIhvcNAQELBQAwVzEL
# MAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UEAxMl
# U2VjdGlnbyBQdWJsaWMgQ29kZSBTaWduaW5nIENBIEVWIFIzNjAeFw0yNjAyMTcw
# MDAwMDBaFw0yNzAyMTcyMzU5NTlaMIG1MRAwDgYDVQQFEwc3OTUxNjgwMRMwEQYL
# KwYBBAGCNzwCAQMTAlVTMRswGQYLKwYBBAGCNzwCAQITCk5ldyBNZXhpY28xHTAb
# BgNVBA8TFFByaXZhdGUgT3JnYW5pemF0aW9uMQswCQYDVQQGEwJVUzETMBEGA1UE
# CAwKTmV3IE1leGljbzEWMBQGA1UECgwNQXJ0SXNXYXIsIExMQzEWMBQGA1UEAwwN
# QXJ0SXNXYXIsIExMQzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMVF
# eTYQb98NCxG5kyp+3X9znsqnixKZzbUdGu0Xi4rjRRryPd3aWUND6TphmpEqb5K1
# HK3OMb+HMgH2Umol43qRxngZFN8UVJYLL6M9ByK9zC5wr7c4dEfH2CkAXrF/PaZF
# Bl7apuOpKg+5rTcEZFd/8xDZkznSgpLEmUBjIP8L1hEKKPWDHMEZZVAh0AX1KW9v
# /Xm5TbXLvtffqr7SPOuVjkOGzZs13bcK7Dq9OCfLBGaOKNbUtU87bVAUpL5uLsun
# Ry9oNISvBsvbaRAP3GuO2IVRDwolQjSgu/onViW7of6RcZAO446lObSC/gjC/lM3
# AxVgVasZlwHrSOwxCoiUaK3tgaZJX05W2wERm4oEGbpE03cTfXzfpPfoil9+uzug
# KR8Pqjk//xeVJMyXn+AcrC7Zq/fS5r2UMoRex5xWV+Bb5EHZ6bdbGcfMtKDlz3vv
# Ze0vB6S/vGsG83V6jGtVM/Co36dErVmhSa7XAahxLsZcTxhlXEpkB6B1qaUuURPH
# gLFEh2r5mYssjMYrO993Q9A1fiwmrLAkhc9nwzLPQrrw1Sxx4d8sBlEf3aGYJe41
# NOLT7I6359adyxhDFr7/vuQCfMby5MRHphYuHVlDQPMbqG+wiTWCwiYVMiuDQJvu
# YYGfgYfauSVf3AA9inrabPDW6KkZA+mJPlCrMFeLAgMBAAGjggGMMIIBiDAfBgNV
# HSMEGDAWgBSBMpJBKyjNRsjEosYqORLsSKk/FDAdBgNVHQ4EFgQUZ8OCbUd0wHpe
# tRPAMtcd9WTyW/8wDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwSQYDVR0gBEIwQDA1BgwrBgEEAbIxAQIBBgEwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwBwYFZ4EMAQMwSwYDVR0f
# BEQwQjBAoD6gPIY6aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# Q29kZVNpZ25pbmdDQUVWUjM2LmNybDB7BggrBgEFBQcBAQRvMG0wRgYIKwYBBQUH
# MAKGOmh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWdu
# aW5nQ0FFVlIzNi5jcnQwIwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28u
# Y29tMA0GCSqGSIb3DQEBCwUAA4IBgQCf2jswDbgZjrjEG2Nb4iHpaUJMxZBjvHEW
# C3fkIdFgDsNtqUudrc+paTNrR7FD2J8Hu1srS75qRTliebxUGBl/QvIaSt1kkRnh
# JQCCD4gYNoncXdIeaFGHEAfQK+HXUCY72y1HdC3CMGINZTQSo+wSNJXJPnSMAOe2
# J0D9Jk+qAkbn1CSjtSX4KHu4Hvfp6dYEKyJx2TfI+Ax+JoOq/v6rq2ca0vFuc3Jm
# wk5T4vqwjZVR/dgy5SAH+WmOqknyKnMmWv5hfTeffQsXwmMMQJUSFN7wsvgzgf1i
# IcW6jktS4+fKiKKScJLOh/Sxnomi0JclNyRood43pyOwmJ90xn7/juj1JdHH4Tf9
# MNeay8vLDqLpwVSVYkuuxm9CO6uvOB2L3wd1Fdw4tFlboHHBOVu7Uo6HkFKwN2kc
# HCN/iExEkG3g0QZUFTUnHoRUmIovu82ODUIAo8E8ej7WOdZQBLnpRSr2fBq/Vhvo
# SfcKe/PE8ZdL8RO+dc5Dca7u0HeABsswgga0MIIEnKADAgECAhANx6xXBf8hmS5A
# QyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxE
# aWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMT
# GERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAx
# MTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5j
# LjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNB
# NDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGPNRcy
# bEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzT
# qpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5AvftB
# dsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3
# mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6z
# MUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS
# 5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBB
# BnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqL
# XvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7ps
# NOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeE
# WvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCC
# AVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQVvYv
# 1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/
# BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0
# LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvI
# tTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwbSI/m
# S83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgX
# f9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liy
# rukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVko43+
# Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2
# ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipD
# oq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRzW6Ax
# nJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAl
# Z66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1
# MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZs
# q8WhbaM2tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0aDAN
# BgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5n
# IFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2MDkw
# MzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVz
# cG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANBG
# rC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdwbHwB
# SOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9RJt/
# 4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrUcCV3
# K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iUSROU
# INDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw2YD3
# w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe46Yce
# NA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seAO+6d
# 2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSHlq8x
# ymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6EaJ+
# AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDchIc2b
# Qhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAMBgNV
# HRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNVHSME
# GDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGlu
# Z1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBp
# bmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIw
# CwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezRCESe
# Y0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0k8FU
# FqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFOtj7Y
# MTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLWU0zi
# TN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2nHkX/
# QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIFeRlq
# AcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqRhoS3
# Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7roan
# cJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47CdxVRd/
# ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/rptb7
# IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL6vdC
# vHlshtjdNXOCIUjsarfNZzGCBkcwggZDAgEBMGswVzELMAkGA1UEBhMCR0IxGDAW
# BgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UEAxMlU2VjdGlnbyBQdWJsaWMg
# Q29kZSBTaWduaW5nIENBIEVWIFIzNgIQU4YrScJSfkPEvu9qaUjyTTANBglghkgB
# ZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJ
# AzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8G
# CSqGSIb3DQEJBDEiBCCnJ+1cTb9R2zUC0SxA+50VqTL4Ty/NgSHU07xmCh1SojAN
# BgkqhkiG9w0BAQEFAASCAgC7xTE6RQQ//i+DfwVKFWrc2txfzuaK+rmKd/QOw9ow
# we95NY86f/6e++6aqk2Ui8TF7tIBye9vUZPHNY3ITM5/gxbWkreuDl2pUUzcKFki
# eOXzBa76EmPGuroPoeo43dYLhcVQ3xxFy2vVquxehCBxOD88CLCdxT0QDaf0FQSu
# sQG4s+33/UP/eJdubTyYlZWG3dW9ledT7vLLuoNwZbKnL15uDiz9tEN4c6SUd69S
# FffXuApjjqdIu3ZTNA+OnRQDRVmjkl/K5gi7/v6hv7zQQM7+ju8MXxWGdTLANV9r
# G//ghRYy4Pmt+mXXvhpOaf2XINvOesrVo03HmPVOQn1Igf876Pi59dc+8c5+PfLQ
# ZRsuHNpn1xFrgj4GASD4XyKhf0avYcsn3R3GF6DmkxjmM+i8zBDf79aecsXLtu/j
# XdexcbUFFLV5j+/cjdkUBfxTqxxakPLA+JNw0Y0Gz3zy14FJtTFZJ5rYe6KoNunD
# qpelJdRcRwsPHMjemKznkU4uHR6x6i/ox2bNNWx2GMIYN2aDhTouUN8B+3C/bWYu
# LRZRNvl43z2BO2Llt73luiCNjHcseyt4sHF+QgRHHYFZ072kAKpqh3bC9SIs75BN
# rkDfbZh01dp7xeR6y3wSr7DYqKw6/RMaEt0UhXKGPmmjWk63qyT1UayPVFh0vTnX
# gKGCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1
# c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA
# 7xhLjfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAzMDgwMTQzNTZaMC8GCSqGSIb3
# DQEJBDEiBCDfEkkRSwFkEJdIcZ2yucpQ+lJ8msnQ0nvP7Ew/qpOxbDANBgkqhkiG
# 9w0BAQEFAASCAgC8djbidG9kmlutCFMSPZOHdfRk1hADNScyU33PmcNRnjMroPqy
# NtdhgUVtN2juR8HtuBEnhITTy8IAQjhQqkuPMZ381l/mIwfI1WzZp0hVzDZesY4Q
# uHGLgVWRpmu5p4PKxj34zN8ShKq2lKn4XQdJOxiqjiErXTnUkKNTrAiZnXAn5/Hh
# gP3ySuuyxM9QTGq8zlCoLM+vkbJ/ujgUO6jnp5GPgvJSu9EIFKbFxd9Zj39lFgHE
# 5ExAlkzQ04U44NfdXQNUJMXUHXiRSrdxIckb0SwdXF3juBAi9YbBPpWukbJwD0yg
# 22VOhWFkzKhuhCenYc6KzBBfTJy5YFm4a9HEnrd6jxvVbwysUFLRHIn3K9eVfvjJ
# 1wqwozLuHG776DEHODXyqyF+xhFgS1ueckt1wURf+z4ADdONkav1S0oVPqnmZ9dv
# ikikbBgbNpw3AOZvTpSmYhQq9wv9x1rM5a3XydYdHCW8mf463wjFm/Cj1+46VCoZ
# 9KXGRsW/x4cv0pyvP14Idgi7koOtiJ38JFA7/WzajAAZmtqxzRcCqDtofFw4Sxgy
# XspgTiUxBcYhh/XCYwJMVDRddvq0gfT9Q9nXWT7C3A4oezYiHiRGQGphXHJ5AaeO
# /ZT3/zYkxqAxagGBfl+f5cXYu4OFItnNsd6D9NgWOYI5OGSpfDhA3u5LCA==
# SIG # End signature block
