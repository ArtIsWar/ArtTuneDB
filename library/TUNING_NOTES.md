# ArtTuneDB Tuning Notes

Library release: 2026.11-MW4

What every tune in this library is, which file to use, and what each tuning style
and Self Gun Level does. This page is written from the tune catalog each time the
library is built, so it matches the files in this folder.

File names are inside the game and version folder they are listed under. For how to
point `config.txt` at a file, see the README. For in-game settings, see
`BF6_SETTINGS.md` and `COD_SETTINGS.md` in this folder.

## Contents

- Battlefield 6 (BF6): V0, V1
- Black Ops 6 (BO6): V6
- Black Ops 6 (PS5) (PS5-BO6): V6
- Black Ops 7 (BO7): V0, V3, V4, V5
- MW4: V1

## Battlefield 6 (BF6)

### BF6 V0 - Version 0 (Launch)

- Folder: `BF6\V0`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `BF6_Target_V0.txt`
- Pre file: `BF6_V0_pre.txt`
- Post file: `BF6_V0_post.txt`
- HeSuVi preset: `BF6_V0.lnk` (EAC Default)
- Loudness Equalization: Release Time 2 (Insta)

### BF6 V1 - Version 1

- Folder: `BF6\V1`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `BF6_Target_V1.txt`
- Pre file: `BF6_V1_pre.txt`
- Post file: `BF6_V1_post.txt`
- HeSuVi preset: `BF6_V1.lnk` (EAC Default)
- Loudness Equalization: Release Time 3 (Quick)

## Black Ops 6 (BO6)

### BO6 V6 - Version 6

- Folder: `BO6\V6`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `BO6_Target_V6.txt`
- Pre file: `BO6_V6_pre.txt`
- Post file: `BO6_V6_post.txt`
- Loudness Equalization: Release Time 2 (Insta)

**HRIR.** Launch the HeSuVi preset shortcut for the one you want.

- **EAC Default** (default): `BO6_V6.lnk`
  Newest, clearest HRIR
- **Atmos**: `BO6_V6_Atmos.lnk`
  Pre BO6 Verdansk HRIR

## Black Ops 6 (PS5) (PS5-BO6)

### PS5-BO6 V6 - Version 6

- Folder: `PS5-BO6\V6`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `PS5-BO6_Target_V6.txt`
- Pre file: `PS5-BO6_V6_pre.txt`
- Post file: `PS5-BO6_V6_post.txt`
- Loudness Equalization: Release Time 2 (Insta)

**HRIR.** Launch the HeSuVi preset shortcut for the one you want.

- **EAC Default** (default): `PS5-BO6_V6.lnk`
- **Atmos**: `PS5-BO6_V6_Atmos.lnk`

## Black Ops 7 (BO7)

### BO7 V0 - Version 0 (Launch)

- Folder: `BO7\V0`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `BO7_Target_V0.txt`
- Pre file: `BO7_V0_pre.txt`
- Post file: `BO7_V0_post.txt`
- HeSuVi preset: `BO7_V0.lnk` (EAC Default)
- Loudness Equalization: Release Time 2 (Insta)

### BO7 V3 - Version 3

- Folder: `BO7\V3`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `BO7_Target_V3.txt`
- Pre file: `BO7_V3_pre.txt`
- Post file: `BO7_V3_post.txt`
- HeSuVi preset: `BO7_V3.lnk` (EAC Default)
- Loudness Equalization: Release Time 2 (Insta)

**Tuning styles.** Swap the pre file in `config.txt` to change tuning style.

- **Competitive** (default): `BO7_V3_pre.txt`
- **Clean**: `BO7_V3_pre_clean.txt`
- **Streamer**: `BO7_V3_pre_streamer.txt`
- **Ultra** (experimental): `BO7_V3_pre_ultra.txt`

### BO7 V4 - Version 4

- Folder: `BO7\V4`
- Type: 8-channel, on the **Art Tune** endpoint, with a HeSuVi stage.
- Target curve: `BO7_Target_V4.txt`
- Pre file: `BO7_V4_pre.txt`
- Post file: `BO7_V4_post.txt`
- HeSuVi preset: `BO7_V4.lnk` (EAC Refined)
- Loudness Equalization: OFF

### BO7 V5 - Version 5

- Folder: `BO7\V5`
- Type: 16-channel, on the **Art Tune +** endpoint. No HeSuVi stage and no Loudness Equalization.
- Target curve: `BO7_Target_V5.txt`
- Start with: `BO7_V5_16ch_ClassicPlus-UltraLoGun.txt`

#### Classic+ (default)

Classic with more footstep lift. The surround and object ceilings are raised so distant steps come through louder, and the boost limiter is relaxed so close steps are no longer held back entirely.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_ClassicPlus-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is not ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_ClassicPlus-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_ClassicPlus-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_ClassicPlus-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_ClassicPlus-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Classic

Competitive's footstep detail and gunfire control with the leveller timing slowed the furthest. The closest thing in the family to the old Loudness Equalization feel, and the least audible processing.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Classic-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is NOT ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Classic-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Classic-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Classic-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Classic-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Open

The least filtered option. Built on Balanced rather than Competitive, so mid-level sound comes up harder and less bright content is held back, with a higher ceiling on the footstep band. Slow leveller timing, so it stays smooth.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Open-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is NOT ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Open-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Open-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Open-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Open-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Full

The world untamed. Combat ducking off, footsteps lifted, full dynamics with nothing holding the peaks back.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Full-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is not ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Full-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Full-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Full-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Full-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Competitive (experimental)

Maximum footstep detail and snap, with bright gunfire tamed the hardest.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Competitive-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is not ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Competitive-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Competitive-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Competitive-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Competitive-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Capped (deprecated)

An older V5 tune, kept for anyone already using it. A hard output clamp on top of the V5 world control, with combat ducking left on. The newer styles hold peaks in check without clamping them.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Capped-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is not ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Capped-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Capped-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Capped-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Capped-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Immersive (deprecated)

An older V5 tune, kept for anyone already using it. The deepest gun taming of the original lineup, which costs it detail. Classic covers the same ground with far less processing.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Immersive-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is not ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Immersive-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Immersive-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Immersive-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Immersive-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

#### Balanced (deprecated)

An older V5 tune, kept for anyone already using it. Open is built directly on it and replaces it.

Self Gun Level:

- **Ultra Low** (default): `BO7_V5_16ch_Balanced-UltraLoGun.txt`
  Your gun pushed to the engine's limit, 6 dB deeper than Low. NOTE: the room reflection after a shot is not ducked at this tier, so with the gun this far down the ring-out can become the loudest thing left.
- **Low**: `BO7_V5_16ch_Balanced-LoGun.txt`
  Your own gunfire tamed the hardest, so shots never bury a footstep. NOTE: Low cuts self gun but reflections from the environment can still be loud, not tunable.
- **Medium**: `BO7_V5_16ch_Balanced-MedGun.txt`
  Your gun pulled back to sit behind the intel. The middle setting.
- **High**: `BO7_V5_16ch_Balanced-HiGun.txt`
  A light trim on your own gunfire. Keeps most of its punch.
- **Extra High**: `BO7_V5_16ch_Balanced-ExtraHiGun.txt`
  Your gun untouched, exactly as the game mixes it.

## MW4

Built for: Warzone, DMZ.

Multiplayer (limited): The tune works in MP, but the Ninja perk and constant chaos make it inconsistent.

### MW4 V1 - Version 1

- Folder: `MW4\V1`
- Type: 16-channel, on the **Art Tune +** endpoint. No HeSuVi stage and no Loudness Equalization.
- Target curve: `MW4_Target_V1.txt`
- Start with: `MW4_V1_16ch_TheaterClear-UltraLoGun_HRIR-KU100.txt`

**HRIR Set.** Every config comes once per head. Pick the head by file name.

- **D1 KU100** (default), file suffix `_HRIR-KU100`:
  The default head, and where new profiles start.
- **D2 KEMAR**, file suffix `_HRIR-KEMAR`:
  The head these tunes were tuned on. Try it if sounds do not place right for you, front against back or high against low.

The file names below are the D1 KU100 versions. For another head, swap
`_HRIR-KU100` in the file name for that head's suffix.

#### Classic LE

The original Loudness Equalization feel, rebuilt as our own leveller, with one change: when you fire, only the front and your gun's copies come down, so the world stays present.

Self Gun Level:

- **Ultra Low** (default): `MW4_V1_16ch_ClassicLE-UltraLoGun_HRIR-KU100.txt`
  Your gun pushed the furthest: the front ducked to the engine's limit and its copies on the object and top channels cut 10 dB. NOTE: a long spray can hold those channels down until you let go.
- **Low**: `MW4_V1_16ch_ClassicLE-LoGun_HRIR-KU100.txt`
  Your own gunfire tamed hard, including its copies on the object and top channels.
- **Medium**: `MW4_V1_16ch_ClassicLE-MedGun_HRIR-KU100.txt`
  Your gun pulled back to sit behind the intel: a light front duck, its echo cut and most of its boom. The middle setting.
- **High**: `MW4_V1_16ch_ClassicLE-HiGun_HRIR-KU100.txt`
  A light touch: a small front duck while you fire, with your gun's echo and a little of its boom cut in the surrounds.
- **Extra High**: `MW4_V1_16ch_ClassicLE-ExtraHiGun_HRIR-KU100.txt`
  Your gun as close to its stock level as the tune gets: no gun duck, and its boom is not cut in the surrounds (explosions keep more of theirs too). The leveller still evens out loud fire.

#### Classic LE Raw

Classic LE with nothing working on the world: the wash and reflection gates are off, so room tails, explosions and your own shot's echo come through as the game mixed them.

Self Gun Level:

- **Ultra Low** (default): `MW4_V1_16ch_ClassicLERaw-UltraLoGun_HRIR-KU100.txt`
  Your gun pushed the furthest: the front ducked to the engine's limit and its copies on the object and top channels cut 10 dB. NOTE: a long spray can hold those channels down until you let go.
- **Low**: `MW4_V1_16ch_ClassicLERaw-LoGun_HRIR-KU100.txt`
  Your own gunfire tamed hard, including its copies on the object and top channels.
- **Medium**: `MW4_V1_16ch_ClassicLERaw-MedGun_HRIR-KU100.txt`
  Your gun pulled back firmly to sit behind the intel: a strong front duck while you fire and a little off its copies on the object and top channels. The middle setting.
- **High**: `MW4_V1_16ch_ClassicLERaw-HiGun_HRIR-KU100.txt`
  Your gun eased back: a moderate front duck while you fire, about what Classic LE's Medium does, and a light cut on its copies on the object and top channels.
- **Extra High**: `MW4_V1_16ch_ClassicLERaw-ExtraHiGun_HRIR-KU100.txt`
  No extra gun duck. The leveller still evens out your gunfire the way Loudness Equalization did, and the world stays up while you fire.

#### Classic LE Raw+

Classic LE Raw with a real Self Gun Level ladder: the world stays as the game mixed it, but from High down the echo of your own shots is cut along with your gun.

Self Gun Level:

- **Ultra Low** (default): `MW4_V1_16ch_ClassicLERawPlus-UltraLoGun_HRIR-KU100.txt`
  Your gun pushed the furthest: the front ducked to the engine's limit and its copies on the object and top channels cut 10 dB. NOTE: a long spray can hold those channels down until you let go.
- **Low**: `MW4_V1_16ch_ClassicLERawPlus-LoGun_HRIR-KU100.txt`
  Your own gunfire and its echo tamed hard, including its copies on the object and top channels.
- **Medium**: `MW4_V1_16ch_ClassicLERawPlus-MedGun_HRIR-KU100.txt`
  Your gun pulled back to sit behind the intel: a light front duck and your own gun's echo cut. The middle setting.
- **High**: `MW4_V1_16ch_ClassicLERawPlus-HiGun_HRIR-KU100.txt`
  A light touch: a small front duck while you fire and a light cut on your own gun's echo.
- **Extra High**: `MW4_V1_16ch_ClassicLERawPlus-ExtraHiGun_HRIR-KU100.txt`
  No gun duck, and your gun's echo comes through as the game mixed it, the same as Classic LE Raw.

#### Classic LE+

Classic LE with footsteps pushed harder: every step's attack stands out about 2 to 3 dB more against the room. Steps stay as loud as in Classic LE while the room, your own steps and your gun sit about 3 dB lower. Other sharp sounds can jump out a little more too.

Self Gun Level:

- **Ultra Low** (default): `MW4_V1_16ch_ClassicLEPlus-UltraLoGun_HRIR-KU100.txt`
  Your gun pushed the furthest: the front ducked to the engine's limit and its copies on the object and top channels cut 10 dB. NOTE: a long spray can hold those channels down until you let go.
- **Low**: `MW4_V1_16ch_ClassicLEPlus-LoGun_HRIR-KU100.txt`
  Your own gunfire tamed hard, including its copies on the object and top channels.
- **Medium**: `MW4_V1_16ch_ClassicLEPlus-MedGun_HRIR-KU100.txt`
  Your gun pulled back to sit behind the intel: a light front duck, its echo cut and most of its boom. The middle setting.
- **High**: `MW4_V1_16ch_ClassicLEPlus-HiGun_HRIR-KU100.txt`
  A light touch: a small front duck while you fire, with your gun's echo and a little of its boom cut in the surrounds.
- **Extra High**: `MW4_V1_16ch_ClassicLEPlus-ExtraHiGun_HRIR-KU100.txt`
  Your gun as close to its stock level as the tune gets: no gun duck, and its boom is not cut in the surrounds (explosions keep more of theirs too). The leveller still evens out loud fire.

#### Theater Clear (default, new)

The game's own mix with footsteps brought forward. The world is left well below where Loudness Equalization would lift it, so quiet moments stay quiet and far sounds stay far. The deep bass stays at the game's level and the sub channel is left out, so steps sit in a cleaner band. The footstep push is smoothed: it lets go of each step gently, so it stays calmer around gunfire and explosions.

Self Gun Level:

- **Ultra Low** (default): `MW4_V1_16ch_TheaterClear-UltraLoGun_HRIR-KU100.txt`
  The most this style takes off your own gun, about half of what Classic LE's Ultra Low does: a moderate front duck, its echo cut and its copies on the object and top channels turned down a little. Light enough that a long spray never pins the front.
- **Low**: `MW4_V1_16ch_TheaterClear-LoGun_HRIR-KU100.txt`
  Your gun clearly pulled back: a light front duck, its echo cut and a little off its copies on the object and top channels.
- **Medium**: `MW4_V1_16ch_TheaterClear-MedGun_HRIR-KU100.txt`
  Your gun eased back: a light front duck while you fire and its echo cut. The middle setting.
- **High**: `MW4_V1_16ch_TheaterClear-HiGun_HRIR-KU100.txt`
  Just a touch: a small front duck while you fire and a light cut on your own gun's echo.
- **Extra High**: `MW4_V1_16ch_TheaterClear-ExtraHiGun_HRIR-KU100.txt`
  Your gun as the game mixed it: no gun duck and nothing cut. The leveller still evens out loud fire.

#### Theater Clear+ (new)

Theater Clear with the footstep push at its sharpest: every step stands about 3 to 4 dB further out of the room, with a fast, hard edge. The room and your own gun sit about 2 dB lower. Other sharp sounds jump out too, and rapid gunfire can flutter.

Self Gun Level:

- **Ultra Low** (default): `MW4_V1_16ch_TheaterClearPlus-UltraLoGun_HRIR-KU100.txt`
  The most this style takes off your own gun, about half of what Classic LE's Ultra Low does: a moderate front duck, its echo cut and its copies on the object and top channels turned down a little. Light enough that a long spray never pins the front.
- **Low**: `MW4_V1_16ch_TheaterClearPlus-LoGun_HRIR-KU100.txt`
  Your gun clearly pulled back: a light front duck, its echo cut and a little off its copies on the object and top channels.
- **Medium**: `MW4_V1_16ch_TheaterClearPlus-MedGun_HRIR-KU100.txt`
  Your gun eased back: a light front duck while you fire and its echo cut. The middle setting.
- **High**: `MW4_V1_16ch_TheaterClearPlus-HiGun_HRIR-KU100.txt`
  Just a touch: a small front duck while you fire and a light cut on your own gun's echo.
- **Extra High**: `MW4_V1_16ch_TheaterClearPlus-ExtraHiGun_HRIR-KU100.txt`
  Your gun as the game mixed it: no gun duck and nothing cut. The leveller still evens out loud fire.
