# Native macOS icon preparation

`AppIcon-Base.png` is a 1024 × 1024, fully opaque, square source layer for
Apple Icon Composer. It deliberately has no alpha corner mask. It preserves the
existing Maccelerate artwork while macOS, rather than `prepare-icon.swift`,
defines the outside curve. Regenerate it with:

```sh
swift dist/prepare-icon.swift dist/MaccelerateIcon-source.png \
  dist/icon-composer/AppIcon-Base.png --icon-composer-layer
```

`AppIcon.icon` was saved with Apple's Icon Composer and is compiled by
`dist/build.sh` using Xcode's `actool`. The compiler produces `Assets.car` and
`AppIcon.icns` for the app's macOS 13 deployment target. The unmasked PNG is
the source for editing the native icon, rather than a pre-clipped `.icns`.
Keep its image layer centered at 0 pt and its root fill near white: shifting
the opaque layer exposed the old blue fill as a hairline at the icon edge.

The current artwork is flattened. Its internal blur and shadow are baked in;
separating the blue Space panes into their own layers would allow Icon Composer
to apply native material effects later. Do not add a corner mask to this layer.

Apple references:

- https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
- https://developer.apple.com/design/human-interface-guidelines/app-icons
