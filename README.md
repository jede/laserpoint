# Laserpoint

A fast, Spotlight/Alfred-style app launcher for macOS. Hit a global hotkey, type
a few letters, and your app launches.

- **⌥Space** to summon the launcher from anywhere
- Fuzzy search over apps in `/Applications` and `/System/Applications`
- "Frecency" ranking — frequently/recently used apps float to the top
- **Calculator** — type an expression (e.g. `12*8+4`) to copy the answer, copy
  the expression, or open it in Calculator
- **Shortcuts** — type a key + text (e.g. `w swift docs`, `c write a haiku`) to
  web-search or open Claude; add your own in Settings
- Auto-launch when your query narrows to a single match (with a brief,
  cancellable confirmation so stray keystrokes don't leak through)
- Lives in the menu bar (no Dock icon)


<img width="864" height="632" alt="image" src="https://github.com/user-attachments/assets/fdf1fd71-b51e-4607-9614-35a0e6abfebf" />


## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) to build from source

## Install

Download the latest `Laserpoint-<version>.dmg` from the
[Releases](../../releases) page, open it, and drag **Laserpoint** to
**Applications**.

> **First launch (unsigned build):** Laserpoint isn't notarized by Apple, so
> Gatekeeper will warn the first time. Right-click the app → **Open** → **Open**,
> or run:
> ```sh
> xattr -dr com.apple.quarantine /Applications/Laserpoint.app
> ```
> You only need to do this once.

## Build from source

```sh
./build.sh run     # build + launch
./build.sh         # build the .app bundle only
```

The binary is ad-hoc signed so it can register its global hotkey.

## Releasing

Releases are produced by GitHub Actions when you push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The `Release` workflow builds a **universal** (Apple Silicon + Intel) `.app`,
packages it into a `.dmg`, and publishes a GitHub Release with auto-generated
notes. To build a DMG locally:

```sh
VERSION=0.1.0 ./build.sh dmg
```

## License

Licensed under the [GNU General Public License v3.0](LICENSE.md).
