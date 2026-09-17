# Num Lock sound assets

The two bundled cues come from [UI SFX](https://uisfx.com/) by romainsimon/Yuki Capital, using the `mechanical` sound pack:

- `toggle-on.ogg` -> Mouse Mode enabled (`Num Lock OFF`)
- `toggle-off.ogg` -> normal NumPad mode restored (`Num Lock ON`)

Upstream repository: https://github.com/romainsimon/uisfx

Upstream manifest version when vendored: `0.4.0`.

Upstream asset paths:

- `packages/uisfx/sounds/mechanical/toggle-on.ogg`
- `packages/uisfx/sounds/mechanical/toggle-off.ogg`

The repository stores the Ogg payloads as Base64 text so the Lua installer can materialize them locally without a network request. `install.lua` and `reinstall.lua` decode them to:

```text
~/.local/share/hyprland_config/sounds/toggle-on.ogg
~/.local/share/hyprland_config/sounds/toggle-off.ogg
```

Audio playback is best-effort through PipeWire `pw-play`; sound failure never blocks Num Lock or Mouse Mode.

The UI SFX generated audio library is CC0-1.0. See `LICENSE-UI-SFX` in this directory.
