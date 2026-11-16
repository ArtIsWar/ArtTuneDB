# 2026.11-MW4

MW4 comes to ArtTuneDB, on a new engine: ATK Spatial Engine Charlie.

**Video walkthrough: https://youtu.be/9GRrP2UsRp4**

- **MW4 V1** is new. It is a 16-channel tune on the **Art Tune +** endpoint,
  built for Warzone and DMZ. It works in multiplayer too, but the Ninja perk
  and the constant chaos there make it less consistent.
- **ATK Spatial Engine Charlie** is the engine behind it. It takes what we
  learned tuning BO7 V5 and reworks it for MW4, with our own leveller in place
  of Windows Loudness Equalization. The headline change is what happens when
  you fire: the world no longer drops out. Only the front, where your gun
  sits, comes down with your shots, so enemy footsteps and everything around
  you stay present. BO7 and every other game stay on the engine they already
  use.
- **Theater** is the game's own mix with footsteps brought forward. Everything
  else is left as the game mixed it, so quiet moments stay quiet and far
  sounds stay far, and the deep bass is held back so footsteps sit in a
  cleaner space. Two styles:
  - **Theater Clear** is the one to start on. It pushes footsteps smoothly and
    lets go of each step gently, so it stays calmer around gunfire and
    explosions.
  - **Theater Clear+** is the sharper version: footsteps are pushed about 3 to
    4 dB harder, with a fast, hard edge. Other sharp sounds jump out too, and
    rapid gunfire can flutter.
- **Classic LE** is the Loudness Equalization feel you know, rebuilt and
  cleaner. Four styles:
  - **Classic LE** is the original feel.
  - **Classic LE+** pushes footsteps harder: every step's attack stands out
    about 2 to 3 dB more, while the room, your own steps and your own gun sit
    about 3 dB lower.
  - **Classic LE Raw** leaves the world alone: room tails, explosions and the
    echo of your own gun come through as the game mixed them.
  - **Classic LE Raw+** is Raw with Self Gun Levels that each make a real
    difference: from High down, the echo of your own shots is cut along with
    your gun.
- **Five Self Gun Levels** on every tuning style, from your gun quietest to
  loudest: Ultra Low, Low, Medium, High, Extra High. Start on Ultra Low.
  Theater's Self Gun Levels are gentler than Classic LE's, and Extra High
  there leaves your gun as the game mixed it.
- **Two HRIR heads.** Every MW4 config comes as a `_HRIR-KU100` file and a
  `_HRIR-KEMAR` file. D1 KU100 is the default. D2 KEMAR is the head these
  tunes were tuned on: try it if sounds do not place right for you, front
  against back or high against low.
- **BO7 V5: Stock is now called Extra High.** It sounds exactly the same, but
  the eight `-StockGun.txt` files are now named `-ExtraHiGun.txt`. See below
  if you use one.
- **Tuning notes.** `library/TUNING_NOTES.md` is new: one page describing
  every tuning style, Self Gun Level and HRIR head in the library, with the
  file to use for each. The installer opens it from the main menu with `[n]`.
- New headphone measurement: Tipsy TS12.
- All other games and versions are unchanged.

## Updating an existing install

Run the setup script and pick **[3] Redownload Library**:

```
irm artiswar.io/tools/ArtTuneGuided | iex
```

It backs up your current library first, including any squig.link EQs you
saved in the `eq\` folders, and prints where the backup went (normally
`Documents\Art Tune Backups\`). Copy your EQ files back into the matching
`eq\` folder afterwards, or the EQ line in your `config.txt` will point at a
file that is no longer there.

## Installer v1.4

- [3] Redownload Library now also installs the plugin files that come with
  the library: new engine files, and any JSFX plugin that has changed. MW4
  needs the new Charlie engine, and until now only a full [1] Install put
  plugin files in place.
- New menu item, **[n] Tuning notes**: opens the description of every tuning
  style and Self Gun Level in your installed library.
- Banner and version updated for this release.

## Setting up MW4

1. In the Windows Sound control panel (Win+R, `mmsys.cpl`), right-click the
   regular **Art Tune** device and disable it. Leave **Art Tune +** alone.
   The two cannot both be enabled while you use MW4.
2. In game, set the sound device to **Art Tune +**, Speaker Output to
   **Windows Default** and Audio Mix to **Headphones**, and leave Enhanced
   Headphone Mode off. The full list is in `library/COD_SETTINGS.md`.
3. Point the 16ch tune line in your `config.txt` at:

   ```
   Include: ArtTuneDB\library\MW4\V1\MW4_V1_16ch_TheaterClear-UltraLoGun_HRIR-KU100.txt
   ```

4. MW4 has its own target curve, `MW4_Target_V1.txt`. Generate your
   squig.link EQ against it and save it in `library\MW4\V1\eq\`.

MW4 ships 60 configs: six tuning styles at five Self Gun Levels, each for two
heads. `library/MW4/V1/Choose a 16ch Tune.txt` describes every tuning style
and Self Gun Level and names the file for each. The files it lists are the KU100 ones; for
KEMAR, change `_HRIR-KU100` in the file name to `_HRIR-KEMAR`. Like BO7 V5,
MW4 does not use Loudness Equalization, so there is no LEQ setting to make.

## If you use BO7 V5

If your `config.txt` points at a file ending `-StockGun.txt`, that file is
gone after the update and the line loads nothing. Change the ending to
`-ExtraHiGun.txt`, for example:

```
Include: ArtTuneDB\library\BO7\V5\BO7_V5_16ch_ClassicPlus-ExtraHiGun.txt
```

Every other V5 file keeps its name, and the V5 target curve is unchanged, so
your existing squig.link EQ still applies.

See [2026.09-V5Styles](https://github.com/ArtIsWar/ArtTuneDB/releases/tag/2026.09-V5Styles)
for the release this builds on.
