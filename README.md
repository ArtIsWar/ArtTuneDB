<p align="center">
  <img width="150" height="150" alt="ArtTuneDB" src="Assets/ArtTuneDBLogo.png" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="License: GPL v3" /></a>
  <a href="library/LICENSE"><img src="https://img.shields.io/badge/library-CC%20BY--NC--SA%204.0-green.svg" alt="Library: CC BY-NC-SA 4.0" /></a>
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6.svg" alt="Platform: Windows 10/11" />
</p>

# ArtTuneDB

Free, open-access database of game audio EQ profiles, HeSuVi configurations, and HRIR files.

See also: [LEQ Control Panel](https://github.com/ArtIsWar/LEQControlPanel) - companion app for managing LEQ state and release time on Art Tune devices.

Check out [youtube.com/artiswar](https://youtube.com/artiswar) for the latest audio guides.

<p align="center">
  <img src="Assets/screenshot.png" alt="ArtTuneDB Installer" width="560" />
</p>

## Requirements

- Windows 10 or 11 (x64 only -- ARM64 not supported)
- PowerShell 5.1 or later (included with Windows)
- Administrator privileges (required for audio driver and registry operations)
- Internet connection (for downloading audio tools during installation)

## Install Script

Run the installer **first**, before downloading the library. Open an **elevated** (Run as Administrator) PowerShell window and run:

```powershell
irm artiswar.io/tools/ArtTuneGuided | iex
```

Or run locally:

```powershell
powershell -ExecutionPolicy Bypass -File Install-ArtTune.ps1
```

The script presents three options:

1. **Voicemeeter Setup** - For USB headphones, DACs, amps, or onboard audio. Installs Hi-Fi Cable, Voicemeeter, ReaPlugs, renames audio endpoints ("Art Tune", "Normal Audio", "Virtual Mix"), Equalizer APO, HeSuVi, EAC_Default.wav HRIR, and LEQ Control Panel. Offers a Fresh Start mode (uninstalls existing audio tools first) or Advanced mode (keeps what's already installed).
2. **Art Tune Approved Device** - Streamlined install for Sound Blaster devices (GC7, G8). Installs ReaPlugs, Equalizer APO, HeSuVi, EAC_Default.wav HRIR, optional Creative App, and LEQ Control Panel. Offers a Fresh Start mode (uninstalls existing E-APO first) or Advanced mode.
3. **Uninstall everything** - Removes all installed components with optional LEQ Control Panel removal. Prompts for system restart.

Desktop shortcut created automatically:

- **ArtTuneDB** - ArtTuneDB folder (contains all tool shortcuts, library, and configuration files)

The script does **not** configure E-APO, Voicemeeter routing, LEQ, or profiles. That is done manually (video guide).

## Library Download

After running the installer, download the latest library release from the [Releases](https://github.com/ArtIsWar/ArtTuneDB/releases) page.

### Release Naming

Releases use CalVer with a game tag. They are tied to game seasons, not semver milestones.

**Format:** `YYYY.MM-GameSeason`

**Examples:**

- `2026.02-BO7-S0` - Launch release with BO7 Season 0 configs
- `2026.04-BO7-S2.5` - Season 2.5 update
- `2026.04-BF6-S2` - BF6 Season 2 additions
- `2026.06-Multi` - Multiple game updates in one release

GitHub's auto-generated source ZIP extracts to `ArtTuneDB-2026.02-BO7-S0/` with everything inside, flat, no nesting.

Inside the extracted folder you'll find a `library/` folder. Copy it into the ArtTuneDB folder and overwrite when prompted. The easiest way is to drag the `library/` folder onto the **ArtTuneDB** desktop shortcut (created by the installer).

After each new library release, repeat this step: drag the `library/` folder onto the ArtTuneDB shortcut or copy the updated `library/` folder into ArtTuneDB and overwrite all files.

### ArtTuneDB Folder

The installer creates the following in the ArtTuneDB root:

| File | Purpose |
|------|---------|
| `ArtIsWar.url` | Opens artiswar.io |
| `ArtTuneDB.url` | Opens the ArtTuneDB GitHub for library downloads and the PowerShell script |
| `E-APO Configuration Editor.lnk` | Opens Equalizer APO Configuration Editor |
| `LEQ Control Panel.lnk` | Launches LEQ Control Panel |
| `README.txt` | Quick reference for the folder contents |
| `library\` | Game EQ profiles and presets -- extract library releases here |

### Library Structure

The library is organized by game, then by season:

```
library/
├── BF6_SETTINGS.md                # Battlefield 6 in-game audio settings
├── COD_SETTINGS.md                # Call of Duty in-game audio settings (BO6/BO7/Warzone)
├── BF6/
│   ├── S0/
│   │   ├── BF6_S0.lnk              # HeSuVi preset shortcut
│   │   ├── BF6_S0_pre.txt          # Pre-HeSuVi processing (7.1 channel)
│   │   ├── BF6_S0_post.txt         # Post-HeSuVi processing (stereo)
│   │   ├── BF6_Target_S0.txt       # Target curve for squig.link
│   │   ├── LEQ - Release Time 2 (Insta).txt #Note file for LEQ settings
│   │   └── eq/                        # Save your squig.link EQ here
│   │       ├── YourHeadphone_BF6_S0.txt
│   │       └── TargetOnly_BF6_S0.txt  # Fallback (no headphone correction)
│   └── S1/
│       └── ...
├── BO6/
│   └── S6/
│       └── ...
├── BO7/
│   └── S0/
│       └── ...
└── measurements/
    ├── README.md                      # Usage instructions
    └── Brand Model.txt                # Headphone frequency response (squig.link format)
```

Each Game/Season folder contains:

| File | Purpose |
|------|---------|
| `*.lnk` | HeSuVi preset shortcut. Launch to load the matching HeSuVi profile. |
| `*_pre.txt` | Pre-HeSuVi processing chain (7.1 channel). Loaded before HeSuVi in config.txt. |
| `*_post.txt` | Post-HeSuVi processing chain (stereo shaping). Loaded at the end of config.txt. |
| `*_Target_*.txt` | Target curve file. Upload to squig.link to generate headphone-specific EQ. |
| `GadgetryTech SquigLink.url` | Opens [gadgetrytech.squig.link](https://gadgetrytech.squig.link) for headphone EQ generation. |
| `LEQ - Release Time *.txt` | A note indicating the recommended LEQ release time value for this config. |
| `eq/` | Folder for headphone EQ files. Save your squig.link Auto EQ results here. |
| `eq/TargetOnly_*.txt` | Fallback EQ that applies the target without headphone-specific correction. |

The `measurements/` folder contains frequency response data for headphones not widely available on squig.link. Upload these alongside a target curve to generate headphone-specific EQ for unlisted models.

### HRIR Files

The `hrir/` folder in this repo contains the EAC_Default.wav HRIR in two sample rates:

| File | Sample Rate |
|------|-------------|
| `hrir/EAC_Default.wav` | 48 kHz |
| `hrir/44/EAC_Default.wav` | 44.1 kHz | (missing from the OG Verdansk guide, sorry :( )

These are automatically downloaded by the install script. If adding them manually, copy the `hrir/` folder contents into `C:\Program Files\EqualizerAPO\config\HeSuVi\hrir\`.

## Configuration

### Pre and Post HeSuVi Files

Each Game/Season folder contains `_pre.txt` and `_post.txt` files:

- **Pre files** handle 7.1 channel processing, applied before HeSuVi convolution.
- **Post files** handle stereo processing and shaping (compression, EQ, limiting), applied after HeSuVi.

Both must be loaded into `config.txt` using the E-APO Configuration Editor:

- Pre file goes **before** the HeSuVi include
- Post file goes at the **very end**

Every game and season should have its matching pre and post files loaded in `config.txt`, even if the files are empty. This keeps your configuration consistent and makes switching between profiles straightforward.

### config.txt

The installer writes a starter `config.txt` (located at `C:\Program Files\EqualizerAPO\config\config.txt`) with placeholder Include lines pointing to `ArtTuneDB\library\`. Browse into the library and replace each path with the real pre, EQ, and post files for your game and season. For example:

```
# PRE HESUVI
Include: ArtTuneDB\library\BO7\S0\BO7_S0_pre.txt
# DO NOT REMOVE HESUVI #
Include: HeSuVi\hesuvi.txt
Include: ArtTuneDB\library\BO7\S0\eq\YourHeadphone_BO7_S0.txt
# POST HESUVI
Include: ArtTuneDB\library\BO7\S0\BO7_S0_post.txt
```

The order matters -- pre, HeSuVi, EQ, post. Do not remove the HeSuVi comment or include line.

### HeSuVi Preset

The matching HeSuVi preset can be launched from the `.lnk` shortcut in the corresponding Game/Season folder.

### Headphone EQ

To generate an EQ profile matched to your specific headphone:

1. Open the `GadgetryTech SquigLink.url` shortcut in the Game/Season folder
2. Upload the target file (e.g., `BF6_Target_S0.txt`) in the **EQ** tab on the left
3. Search for your headset or IEM
   - If your headphone isn't listed on squig.link, check the `measurements/` folder or use the `TargetOnly_*.txt` directly in the EQ field of the config file with the file in the `eq/` folder, as a last resort. This applies the target curve without headphone-specific correction -- it's better than no EQ, but won't be as accurate as a matched profile.
4. Hit **Auto EQ**
5. Save the result as `YourHeadphone_BO7_S0.txt` (matching the game and season you're tuning for)
6. Place the file in the `eq/` subfolder inside the Game/Season folder

### LEQ Release Time

Each Game/Season folder contains a file like `LEQ - Release Time 2 (Insta).txt` that indicates the recommended LEQ release time value for that configuration. Set the LEQ state and Release Time on the Art Tune device using [LEQ Control Panel](https://github.com/ArtIsWar/LEQControlPanel).

### In-Game Settings

Each game has required in-game audio settings for the processing chain to work correctly. Reference files are in the library root:

| File | Covers |
|------|--------|
| `library/BF6_SETTINGS.md` | Battlefield 6 -- Volume Mixer routing, 7.1 Surround, volume levels, audio mix |
| `library/COD_SETTINGS.md` | Black Ops 7, Black Ops 6, Warzone -- device selection, 7.1 Surround, Enhanced Headphone Mode off |

Open the matching settings file for your game and apply the listed values before playing. Incorrect in-game settings (wrong output device, stereo instead of 7.1, Enhanced Headphone Mode on) will bypass or break the processing chain.

## Third-Party Software

| Software | Purpose | License | Link |
|----------|---------|---------|------|
| [Equalizer APO](https://sourceforge.net/projects/equalizerapo/) | System-wide audio processing engine | GPL-2.0 | [SourceForge](https://sourceforge.net/projects/equalizerapo/) |
| [HeSuVi](https://sourceforge.net/projects/hesuvi/) | Virtual surround (HRIR convolution) for headphones | GPL-2.0 | [SourceForge](https://sourceforge.net/projects/hesuvi/) |
| [ReaPlugs](https://www.reaper.fm/reaplugs/) | VST audio plugins (compressor, EQ, limiter) | Freeware (REAPER license) | [reaper.fm](https://www.reaper.fm/reaplugs/) |
| [Hi-Fi Cable](https://vb-audio.com/Cable/) | Virtual audio cable for routing | Donationware | [vb-audio.com](https://vb-audio.com/Cable/) |
| [Voicemeeter](https://vb-audio.com/Voicemeeter/) | Virtual audio mixer | Donationware | [vb-audio.com](https://vb-audio.com/Voicemeeter/) |
| [Creative App](https://support.creative.com/Downloads/) | Sound Blaster device management (GC7/G8 setup path) | Proprietary (free) | [creative.com](https://support.creative.com/Downloads/) |
| [LEQ Control Panel](https://github.com/ArtIsWar/LEQControlPanel) | Manages LEQ state and release time on Art Tune devices | GPL-3.0 | [GitHub](https://github.com/ArtIsWar/LEQControlPanel) |

These tools are downloaded during installation and are subject to their own license terms.
ArtTuneDB does not bundle or redistribute these tools -- they are fetched from their official sources at install time.

### HRIR Attribution

The **EAC_Default.wav** HRIR preset was generated using [Individualized HRTF Synthesis](https://github.com/davircarvalho/Individualized_HRTF_Synthesis) by Davi Carvalho (Federal University of Santa Maria, Brazil). The synthesis tool is licensed under GPL-3.0. The generated HRIR output (`.wav` file) is redistributed as data, not as a derivative of the tool's source code.

## License

This repository is dual-licensed:

- **Scripts** (`powershell/`) -- [GNU General Public License v3.0](LICENSE)
- **Audio configurations** (`library/`) -- [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](library/LICENSE)

See each LICENSE file for full terms.
