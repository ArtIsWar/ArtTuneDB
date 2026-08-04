# MIGRATION MANIFEST -- 2026.07-Overhaul

Working-tree-only change set: V-token library migration (Phase 1) plus the documentation
set (Phase 2), followed by a targeted fix to the BO6 HeSuVi headers. No git operations were
performed (no commit, push, branch, checkout, tag, stash, fetch, merge, or pull). All changes
are left uncommitted for review.

Source of migrated library content: `C:\dev\_ATK BETA LIBRARY\LibraryWorksheet-v\library\`
Destination: `C:\dev\ArtTuneDB\library\`

## Git safety

| Check | Pre | Post | Status |
|-------|-----|------|--------|
| Branch | main | main | unchanged |
| HEAD | 5af0e9a (fix: BO7 S3 treble correction) | 5af0e9a | unchanged |
| Stash entries | 0 | 0 | unchanged |
| Staged files | 0 | 0 | nothing staged |

Working-tree changes only. HEAD, branch, and stash are untouched.

## Counts

| Category | Count | Notes |
|----------|-------|-------|
| Files removed | 53 | The legacy S-prefix corpus (4 game folders, 16 dirs). |
| Files added (new / untracked) | 301 | 298 migration-copied + `library/vst/LICENSE` + `RELEASE_NOTES_2026.07-Overhaul.md` + this manifest. |
| Files replaced (content changed) | 2 | `library/changelog.txt`, `README.md`. |
| Files copied-but-identical (no net change) | 3 | `library/BF6_SETTINGS.md`, `library/COD_SETTINGS.md`, `library/LICENSE` (byte-identical to repo copies; do not appear in git status). |
| Files kept untouched | 26 | `library/measurements/` (left as-is by decision). |

Added-file breakdown (298 migration-copied): catalog.json (1), game-configs\ (39),
Targets\ (10), hesuvi\ (21 = 17 .lnk + 4 .wav), vst\ (2 DLLs), jsfx\ (2), equalizer\ (223).
Plus Phase 2 new files: library/vst/LICENSE (1), RELEASE_NOTES_2026.07-Overhaul.md (1),
and MIGRATION-MANIFEST.md (this file). Byte-verbatim integrity of all 302 copied items
(298 tree/single files + the 4 already-existing settings/changelog/LICENSE targets) was
confirmed at copy time by SHA-256 source-vs-destination reconciliation: 0 mismatches.

Post-copy correction: `library/game-configs/BO6/BO6_V6_pre.txt` and `BO6_V6_post.txt` were
intentionally edited AFTER the byte-verbatim copy to fix a dangling HeSuVi header (see
verification 2b). They now differ from the worksheet source by the `BO6-S6` -> `BO6_V6`
token correction only (2 bytes per occurrence, 3 occurrences per file = 12 bytes total;
file sizes unchanged: 876 and 1,158 bytes). These two files remain untracked, so this does
not change the git counts above.

Also post-copy: the 20 BO7 V5 16ch configs (game-configs/BO7/BO7_V5_16ch_*.txt) had their developer/param header notes replaced with user-facing notes derived from catalog.json (### TUNE / ### SELF GUN / ### OUTPUT lines), applied identically to the repo and the worksheet source so the two stay byte-identical. The VSTPlugin ChunkData preset lines are untouched and each file's original line-endings were preserved (14 CRLF, 6 LF). These files remain untracked, so the git counts above are unchanged.

## Excluded from the migration (by spec)

- `version.txt` (beta V-ATK stamp) -- not copied. Confirmed absent in destination.
- `catalog.json.bak-20260714-193122` (timestamped backup) -- not copied. Confirmed absent.
- `measurements\` (worksheet copy, ~130 MB / 13,260 files incl. AutoEq\ + Squiglink\ mirrors)
  -- NOT merged, by user decision. `library/measurements/` retains the repo's 26 curated files
  unchanged.

## Removed-file list (the S-prefix corpus, 53 files / 16 dirs)

```
library\BF6\S0\BF6_S0_post.txt
library\BF6\S0\BF6_S0_pre.txt
library\BF6\S0\BF6_S0.lnk
library\BF6\S0\BF6_Target_S0.txt
library\BF6\S0\Edit E-APO Config.lnk
library\BF6\S0\eq\TargetOnly_BF6_S0.txt
library\BF6\S0\GadgetryTech SquigLink.url
library\BF6\S0\LEQ - Release Time 2 (Insta).txt
library\BF6\S1\BF6_S1_post.txt
library\BF6\S1\BF6_S1_pre.txt
library\BF6\S1\BF6_S1.lnk
library\BF6\S1\BF6_Target_S1.txt
library\BF6\S1\Edit E-APO Config.lnk
library\BF6\S1\eq\TargetOnly_BF6_S1.txt
library\BF6\S1\GadgetryTech SquigLink.url
library\BF6\S1\LEQ - Release Time 3 (Quick).txt
library\BO6\S6\BO6_S6_Atmos.lnk
library\BO6\S6\BO6_S6_post.txt
library\BO6\S6\BO6_S6_pre.txt
library\BO6\S6\BO6_S6.lnk
library\BO6\S6\BO6_Target_S6.txt
library\BO6\S6\Edit E-APO Config.lnk
library\BO6\S6\eq\TargetOnly_BO6_S6.txt
library\BO6\S6\GadgetryTech SquigLink.url
library\BO6\S6\LEQ - Release Time 2 (Insta).txt
library\BO7\S0\BO7_S0_post.txt
library\BO7\S0\BO7_S0_pre.txt
library\BO7\S0\BO7_S0.lnk
library\BO7\S0\BO7_Target_S0.txt
library\BO7\S0\Edit E-APO Config.lnk
library\BO7\S0\eq\TargetOnly_BO7_S0.txt
library\BO7\S0\GadgetryTech SquigLink.url
library\BO7\S0\LEQ - Release Time 2 (Insta).txt
library\BO7\S3\BO7_S3_post.txt
library\BO7\S3\BO7_S3_pre_clean.txt
library\BO7\S3\BO7_S3_pre_streamer.txt
library\BO7\S3\BO7_S3_pre_ultra.txt
library\BO7\S3\BO7_S3_pre.txt
library\BO7\S3\BO7_S3.lnk
library\BO7\S3\BO7_Target_S3.txt
library\BO7\S3\Edit E-APO Config.lnk
library\BO7\S3\eq\TargetOnly_BO7_S3.txt
library\BO7\S3\GadgetryTech SquigLink.url
library\BO7\S3\LEQ - Release Time 2 (Insta).txt
library\PS5-BO6\S6\Edit E-APO Config.lnk
library\PS5-BO6\S6\eq\TargetOnly_PS5-BO6_S6.txt
library\PS5-BO6\S6\GadgetryTech SquigLink.url
library\PS5-BO6\S6\LEQ - Release Time 2 (Insta).txt
library\PS5-BO6\S6\PS5-BO6_S6_Atmos.lnk
library\PS5-BO6\S6\PS5-BO6_S6_post.txt
library\PS5-BO6\S6\PS5-BO6_S6_pre.txt
library\PS5-BO6\S6\PS5-BO6_S6.lnk
library\PS5-BO6\S6\PS5-BO6_Target_S6.txt
```

## Replace-or-identical results (settings / changelog / library LICENSE)

| File | Repo (pre) | Worksheet (src) | Result |
|------|-----------|-----------------|--------|
| BF6_SETTINGS.md | D7555BD2E287 | D7555BD2E287 | IDENTICAL (no net change) |
| COD_SETTINGS.md | 7AE0D40F066B | 7AE0D40F066B | IDENTICAL (no net change) |
| library/LICENSE | ADA4C735C5BC | ADA4C735C5BC | IDENTICAL (byte-identical CC BY-NC-SA, as expected) |
| changelog.txt | 2F441B2F49E3 (708 B) | 1B50909BED2B (2,560 B) | REPLACED (worksheet wins; then prepended in Phase 2 D1) |

(SHA-256, first 12 hex shown.)

## jsfx byte-diff (worksheet -> library/jsfx/ vs existing repo-root jsfx/)

| File | Repo-root jsfx/ | Worksheet jsfx/ | Result |
|------|-----------------|-----------------|--------|
| atk_spatial_engine.jsfx | 674A1C2519E8 (82,623 B) | 8DDF1FDA8749 (80,779 B) | DIFFERENT -- worksheet copied into library/jsfx/ |
| atk_stereo_spatial_enhancer.jsfx | 5F3A31EF8D95 (21,299 B) | 977A2C647BAD (20,602 B) | DIFFERENT -- worksheet copied into library/jsfx/ |

Notes: `library/jsfx/` is a new self-contained copy of the worksheet plugins. The repo-root
`jsfx/` (installer source) was left untouched. Repo-root `jsfx/` also carries a `LICENSE`
file that the worksheet `jsfx/` does not; `library/jsfx/` therefore has no LICENSE (worksheet
copied verbatim). The distinct proprietary VST LICENSE created in Phase 2 lives at
`library/vst/LICENSE`, covering the Bravo DLLs, not the JSFX plugins.

## Phase 1 verification results

Final status: ALL 5 CHECKS PASS (check 2b passes after the BO6 dangling-header fix applied in
this pass; see 2b below).

1. Catalog resolution -- PASS. All 89 file references in catalog.json resolve to existing
   files (26 configFile, 31 lnkFile, 13 preFile, 9 postFile, 10 targetFile), including the
   recursion through variations / subVariations / hrirOptions (BO7 V5's 20 16-channel
   configFiles, STD's Flat_Target.txt, all atmos hrirOptions lnks).

2. HRIR chain:
   - 2a PASS -- all 16 catalog lnkFiles present in library/hesuvi/profiles/.
   - 2b PASS (after fix) -- all 17 primary `### HESUVI:` headers resolve (7 distinct).
     Initially FAILED: `library/game-configs/BO6/BO6_V6_pre.txt` and `BO6_V6_post.txt` named
     `BO6-S6.lnk` on line 1 (the old dash/S-token name the S->V rename missed), while the
     shipped profile is `BO6_V6.lnk`. FIXED in this pass -- every `BO6-S6` token in both files
     was corrected to `BO6_V6` (byte-exact, CRLF and file size preserved). The primary header
     now resolves to `BO6_V6.lnk`; the `### HESUVI_ALT:` and "To use v2 HRIR" instruction
     lines were renamed to `BO6_V6_v2.lnk`, matching the V-token pattern used by BF6 and
     PS5-BO6. catalog.json already referenced BO6_V6.lnk correctly (see 2a) and was not changed.
   - 2b INFO -- non-shipped `### HESUVI_ALT:` alternative-HRIR references (expected-absent, as
     for all games): BF6_V1_v2.lnk, BO6_V6_v2.lnk, PS5-BO6_V6_v2.lnk (BF6_V1, BO6_V6,
     PS5-BO6_V6 pre/post). These `_v2` alternate profiles intentionally do not ship.
   - 2c PASS -- library-shipped HRIRs [EAC_Default, EAC_Refined] present in BOTH
     library/hesuvi/hrir/ and library/hesuvi/hrir/44/. The HeSuVi built-in HRIRs invoked by
     the .lnk files (`atmos-`, `sonic-`, `none`) are expected-absent from the library
     (they resolve inside the HeSuVi install) -- reported, not a failure.
   - 2d PASS -- EAC_Refined.wav confirmed present at both 48 kHz and 44.1 kHz.

3. VST presence -- PASS. Both atk_spatial_engine_bravo_v1.0.2.dll and
   atk_spatial_engine_bravo_v2_0_0.dll present in library/vst/.

4. No S-prefix remnants -- PASS. Zero `_S[0-9]` files and zero `S[0-9]` season folders under
   library/ (measurements/ excepted).

## Phase 2 deliverables

- D1 -- `library/changelog.txt`: prepended a `## 2026.07-Overhaul` entry above the newest
  entry. Heading style used: H2 `## <token>`, matching the migrated worksheet changelog's
  existing style (its entries are `## 2026.06.95-V`, `## 2026.06.91-V`). The provided
  non-beta heading `## 2026.07-Overhaul` was used verbatim (no `-V` suffix added). Old
  entries were NOT scrubbed and no banner line was added. Original 2,560 bytes preserved
  exactly as a suffix; CRLF / no-BOM preserved.
  Beta-era version tokens DO remain in changelog history: `## 2026.06.95-V`,
  `## 2026.06.91-V`, and a "Beta note:" line in the 2026.06.91-V entry. Left untouched by design.

- D2 -- `RELEASE_NOTES_2026.07-Overhaul.md` (new, repo root): created with the specified
  skeleton content, including the `TODO-FINALIZE` marker (retained by design). UTF-8 no BOM,
  CRLF, newline-terminated, matching RELEASE_NOTES_2026.04.md conventions.

- D3 -- `library/vst/LICENSE` (new): proprietary binary-only license for the ATK Spatial
  Engine Bravo DLLs, verbatim content. UTF-8 no BOM, CRLF, newline-terminated.

- D4 -- `README.md` (two surgical edits, nothing else touched):
  - Edit A (Third-Party Software table): appended one row after the LEQ Control Panel row.
    Before (last row): `| [LEQ Control Panel](...) | Manages LEQ state and release time on Art Tune devices | GPL-3.0 | [GitHub](...) |`
    After adds: `| ATK Spatial Engine Bravo (VST) | Native spatial audio processing engine (8ch / 16ch) | Proprietary (binary-only) | [LICENSE](library/vst/LICENSE) |`
    The Purpose cell ("Native spatial audio processing engine (8ch / 16ch)") is the one
    necessary judgment (the spec supplied name, license, and the LICENSE link only); phrased
    to mirror the Equalizer APO row.
  - Edit B (Headphone EQ section, line 237): the TargetOnly sentence changed from
    "This applies the target curve without headphone-specific correction ..." to
    "This applies a flat target curve (now shared across all games, no longer per-game)
    without headphone-specific correction ...". Minimal one-sentence edit; section not
    restructured.

No em dashes were introduced in any Phase 2 content. All edited/created files are UTF-8
without BOM; existing bytes outside the edit regions were preserved.

## Follow-up flags (out of scope this pass; recorded for a later pass)

1. RESOLVED (both trees): the BO6 primary `### HESUVI:` dangling header was corrected --
   `BO6-S6` -> `BO6_V6` in `library/game-configs/BO6/BO6_V6_pre.txt` and `BO6_V6_post.txt`.
   RESOLVED (worksheet too): the same fix was later applied to the worksheet source (game-configs/BO6/BO6_V6_pre.txt and BO6_V6_post.txt), which are now byte-identical to the repo copies, so a future re-migration will not reintroduce the dangle.
2. README.md still describes the retired S-prefix era in its Library Structure, Release
   Naming, Install Script, and (most of) Configuration sections, including config.txt
   Include example paths like `ArtTuneDB\library\BO7\S3\BO7_S3_pre.txt` that no longer exist
   in the new raw layout. Left stale by design; pending the installer rebuild pass.
3. `dev-tools/Build-ArtTuneDB.ps1` builds the old S-prefix distribution format and is now
   inconsistent with the raw catalog-driven layout now in library/. Not edited (gitignored).
4. `RELEASE_NOTES_2026.07-Overhaul.md` retains its `TODO-FINALIZE` line by design (installer
   version, exact component list, counter endpoint details pending the installer rebuild).
5. README Edit A adds the ATK Spatial Engine Bravo (ArtIsWar's own proprietary software) to a
   table titled "Third-Party Software" per the explicit instruction; semantically it is
   first-party. Also, the note under that table ("ArtTuneDB does not bundle or redistribute
   these tools -- they are fetched from their official sources at install time") is now
   partially inaccurate, since the VST binaries ARE bundled in library/vst/. Both left as-is
   (outside the one-row edit scope).
6. Doc-vs-tree gap: D1/D4 state that per-game TargetOnly is retired in favor of a flat target,
   but the migrated tree still ships per-game files at
   `library/equalizer/targetonly/TargetOnly_*.txt` (6 files: BF6_V0, BF6_V1, BO6_V6, BO7_V0,
   BO7_V3, PS5-BO6_V6). Content change reflects intended direction ahead of the equalizer
   restructure.

## Other informational notes

- Added alongside this commit: three VB-CABLE endpoint device icons in Assets/ (ArtTuneCable.ico, ArtTunePlusCable.ico, ArtTuneUnifiedOutput.ico), copied byte-verbatim from ArtTuneKit.App/Resources/Icons/.
- Unreferenced-but-shipped files carried over verbatim as part of the complete folder copies:
  `library/Targets/BO7_Target_V3v2.txt` and `library/hesuvi/profiles/Stereo_Bypass.lnk`
  (present on disk, not referenced by catalog.json).
- All 17 profile `.lnk` files hard-code the absolute TargetPath
  `C:\Program Files\EqualizerAPO\config\HeSuVi\HeSuVi.exe` (environmental dependency).
- No `library/equalizer/` profiles exist for BO7 V4, BO7 V5, or the STD seasons (expected;
  those tunes render natively or use flat/Target-only EQ).

## git status --short at completion

The listing below was captured immediately before this manifest was written; this file
(`MIGRATION-MANIFEST.md`) is therefore one additional untracked entry not shown below. The
BO6 header fix does not change this listing (the two BO6 files remain untracked under the
`?? library/game-configs/` rollup).

```
 M README.md
 D library/BF6/S0/BF6_S0.lnk
 D library/BF6/S0/BF6_S0_post.txt
 D library/BF6/S0/BF6_S0_pre.txt
 D library/BF6/S0/BF6_Target_S0.txt
 D "library/BF6/S0/Edit E-APO Config.lnk"
 D "library/BF6/S0/GadgetryTech SquigLink.url"
 D "library/BF6/S0/LEQ - Release Time 2 (Insta).txt"
 D library/BF6/S0/eq/TargetOnly_BF6_S0.txt
 D library/BF6/S1/BF6_S1.lnk
 D library/BF6/S1/BF6_S1_post.txt
 D library/BF6/S1/BF6_S1_pre.txt
 D library/BF6/S1/BF6_Target_S1.txt
 D "library/BF6/S1/Edit E-APO Config.lnk"
 D "library/BF6/S1/GadgetryTech SquigLink.url"
 D "library/BF6/S1/LEQ - Release Time 3 (Quick).txt"
 D library/BF6/S1/eq/TargetOnly_BF6_S1.txt
 D library/BO6/S6/BO6_S6.lnk
 D library/BO6/S6/BO6_S6_Atmos.lnk
 D library/BO6/S6/BO6_S6_post.txt
 D library/BO6/S6/BO6_S6_pre.txt
 D library/BO6/S6/BO6_Target_S6.txt
 D "library/BO6/S6/Edit E-APO Config.lnk"
 D "library/BO6/S6/GadgetryTech SquigLink.url"
 D "library/BO6/S6/LEQ - Release Time 2 (Insta).txt"
 D library/BO6/S6/eq/TargetOnly_BO6_S6.txt
 D library/BO7/S0/BO7_S0.lnk
 D library/BO7/S0/BO7_S0_post.txt
 D library/BO7/S0/BO7_S0_pre.txt
 D library/BO7/S0/BO7_Target_S0.txt
 D "library/BO7/S0/Edit E-APO Config.lnk"
 D "library/BO7/S0/GadgetryTech SquigLink.url"
 D "library/BO7/S0/LEQ - Release Time 2 (Insta).txt"
 D library/BO7/S0/eq/TargetOnly_BO7_S0.txt
 D library/BO7/S3/BO7_S3.lnk
 D library/BO7/S3/BO7_S3_post.txt
 D library/BO7/S3/BO7_S3_pre.txt
 D library/BO7/S3/BO7_S3_pre_clean.txt
 D library/BO7/S3/BO7_S3_pre_streamer.txt
 D library/BO7/S3/BO7_S3_pre_ultra.txt
 D library/BO7/S3/BO7_Target_S3.txt
 D "library/BO7/S3/Edit E-APO Config.lnk"
 D "library/BO7/S3/GadgetryTech SquigLink.url"
 D "library/BO7/S3/LEQ - Release Time 2 (Insta).txt"
 D library/BO7/S3/eq/TargetOnly_BO7_S3.txt
 D "library/PS5-BO6/S6/Edit E-APO Config.lnk"
 D "library/PS5-BO6/S6/GadgetryTech SquigLink.url"
 D "library/PS5-BO6/S6/LEQ - Release Time 2 (Insta).txt"
 D library/PS5-BO6/S6/PS5-BO6_S6.lnk
 D library/PS5-BO6/S6/PS5-BO6_S6_Atmos.lnk
 D library/PS5-BO6/S6/PS5-BO6_S6_post.txt
 D library/PS5-BO6/S6/PS5-BO6_S6_pre.txt
 D library/PS5-BO6/S6/PS5-BO6_Target_S6.txt
 D library/PS5-BO6/S6/eq/TargetOnly_PS5-BO6_S6.txt
 M library/changelog.txt
?? RELEASE_NOTES_2026.07-Overhaul.md
?? library/Targets/
?? library/catalog.json
?? library/equalizer/
?? library/game-configs/
?? library/hesuvi/
?? library/jsfx/
?? library/vst/
```
