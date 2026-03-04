# 🎮 Battlefield 6: In-Game Audio Settings

> These settings are **required** for the audio processing chain to work correctly.

---

## ⚠️ Volume Mixer Setup (REQUIRED)

**BF6 has no in-game audio device selector.** You have to route it manually through Windows:

1. Open **Settings → System → Sound → Volume Mixer**
2. Find **Battlefield 6** in the app list
3. Set its output device to **Art Tune**

Without this step, BF6 audio bypasses the processing chain entirely.

> 💡 If BF6 doesn't appear in Volume Mixer, launch the game first, then check again.

---

## Audio Settings

| Setting | Value | |
|---|---|---|
| Master Volume | **100** | ⚠️ REQUIRED |
| Sound Effects Volume | **100** | ⚠️ REQUIRED |
| Music Volume | **0** | |
| Menu Music Volume | **0** | |
| Sound System | **7.1 Surround** | ⚠️ REQUIRED |
| Audio Mix | **High Dynamics** | Recommended |
| External VOIP Output | **Enabled** | |
| Output Device | **Normal Audio** | Any non-Art Tune device |

---

### Why These Matter

- **Volume Mixer routing** is the only way to get BF6 audio into the processing chain. No in-game option exists.
- **Master / SFX at 100** is required. The processing chain handles volume leveling via LEQ. Turning these down starves the chain of signal.
- **7.1 Surround** is required. HeSuVi needs all channels to create the binaural spatial image.
- **External VOIP Output** routes voice chat to Normal Audio so comms bypass the processing chain and sound natural.
- **Audio Mix** is personal preference, but start with High Dynamics. It's the best baseline for competitive play.
- **Music / Menu Music at 0** keeps the audio channel clean for competitive play. No music masking footsteps or cues.
