# App assets

- `LockHoldIcon.png` is the full-size source artwork.
- `LockHold.iconset/` contains the standard-resolution and Retina PNG variants.
- `LockHold.icns` is the compiled icon used by the app bundle.
- `Info.plist` is the canonical bundle metadata copied by the build script.

After updating the PNG variants, regenerate the compiled icon on macOS:

```sh
iconutil --convert icns Assets/LockHold.iconset --output Assets/LockHold.icns
```

The menu bar uses SF Symbols supplied by macOS at runtime. Those system symbols
are not embedded in the repository's artwork or redistributed as image files.
