# 🎮 Call of Duty: In-Game Audio Settings

> Applies to **Black Ops 7**, **Black Ops 6**, and **Warzone**
>
> These settings are **required** for the audio processing chain to work correctly.

---

## Audio Tab

| Setting | Value | |
|---|---|---|
| Audio Output Device | **Art Tune (Game)** | |
| Speaker Output | **7.1 Surround** | ⚠️ REQUIRED |
| Audio Mix | **Headphones Bass Cut** | Recommended |
| Master Volume | **100** | |
| Effects Volume | **100** | |
| Music Volume | **0** | |
| Menu Music Volume | **0** | |
| Enhanced Headphone Mode | **OFF** | ⚠️ REQUIRED |
| Mono Audio | **OFF** | ⚠️ REQUIRED |

## Voice Tab

| Setting | Value | |
|---|---|---|
| Voice Output Device | **Normal Audio (Voice)** | Any non-Art Tune device |

---

### Why These Matter

- **7.1 Surround** is required. HeSuVi needs all 8 channels to create the binaural spatial image. Stereo input = no directional audio.
- **Enhanced Headphone Mode / Mono Audio** collapse or alter the surround signal before it reaches the processing chain.
- **Art Tune (Game)** routes audio through E-APO. If your game outputs to any other device, the processing chain is bypassed entirely.
- **Voice on Normal Audio** keeps comms out of the processing chain so voices sound natural.
- **Audio Mix** is personal preference, but start with Headphones Bass Cut. It's the best baseline for competitive play.
