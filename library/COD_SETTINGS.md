# 🎮 Call of Duty: In-Game Audio Settings

> Applies to **Black Ops 7**, **Black Ops 6**, and **Warzone**
>
> These settings are **required** for the audio processing chain to work correctly.

---

## Audio Tab

| Setting | Value | |
|---|---|---|
| Game Sound Device | **Art Tune** (V0-V4) / **Art Tune +** (V5) | ⚠️ REQUIRED |
| Speaker Output | **Windows Default** | ⚠️ REQUIRED |
| Master Volume | **100** | |
| Effects Volume | **100** | |
| Dialog Volume | **100** | Flexible |
| Music Volume | **0** | Recommended |
| Menu Music Volume | **0** | Recommended |
| Audio Mix | **Headphones Bass Cut** | Recommended |
| Enhanced Headphone Mode | **OFF** | ⚠️ REQUIRED |
| Asymmetrical Hearing Compensation | **OFF** | |
| Mono Audio | **OFF** | ⚠️ REQUIRED |

### Which device do I pick?

| Your tune | Game Sound Device |
|---|---|
| BO7 V0, V3, V4 (and every earlier version) | **Art Tune** |
| BO7 V5 | **Art Tune +** |
| Black Ops 6, Warzone on a pre-V5 tune | **Art Tune** |
| Warzone on a BO7 V5 tune | **Art Tune +** |

If you switch between V0-V4 and V5, change the in-game device to match.

Black Ops 6 has no Enhanced Headphone Mode or Asymmetrical Hearing Compensation setting.
Everything else on this page applies to it unchanged.

## Voice Tab

| Setting | Value | |
|---|---|---|
| Voice Chat Output Device | **Your normal hardware device** | NOT Art Tune or Art Tune + |

---

### Why These Matter

- **Speaker Output on Windows Default** is required. It lets the game follow the format of the
  endpoint it is playing to, which is 7.1 on Art Tune and 16 channels on Art Tune +. Forcing a
  fixed layout here overrides that and breaks Art Tune game-audio routing.
- **Art Tune / Art Tune +** is the way into the processing chain. If the game outputs to any
  other device, the chain is bypassed entirely and you hear stock audio.
- **Enhanced Headphone Mode / Mono Audio** collapse or alter the surround signal before it
  reaches the chain, so 7.1 and 16-channel processing cannot work.
- **Asymmetrical Hearing Compensation** changes the left / right balance ahead of the chain.
  Leave it off so the tune receives a neutral signal.
- **Master and Effects at 100** give the chain full signal to work with. Turning them down
  starves it and you lose detail the tune is meant to bring out.
- **Voice on your normal hardware device** keeps comms out of the processing chain so voices
  sound natural.
- **Audio Mix** is personal preference, but start with Headphones Bass Cut. It's the best
  baseline for competitive play.
- **Music / Menu Music at 0** keeps the channel clean for competitive play. No music masking
  footsteps or cues.
