# Local branding

The public app and icon use macOS system lettering. Optional font files and private wordmarks are ignored by Git.

For your own appropriately licensed branding, place a vector wordmark at `Resources/kol-chen-logo.pdf` before building. `MakeWordmark.swift` can generate this file from a font you have permission to use:

```sh
xcrun swift MakeWordmark.swift /path/to/licensed-font.otf Resources
```

To regenerate the app icon after changing your local branding:

```sh
mkdir -p build
xcrun swift MakeIcon.swift build/kol-chen.iconset
iconutil -c icns build/kol-chen.iconset -o AppIcon.icns
zsh build.sh
```

Ben Natan granted the author specific permission to use Popper only for demonstrations on his blog. That permission is not a font license for other users or for redistribution. No Popper font binary or private Popper wordmark is distributed here.
