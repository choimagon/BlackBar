# BlackBar

BlackBar is a lightweight macOS menu bar utility that makes the notch and top menu bar background appear black while keeping menu bar items visible.

Repository: https://github.com/choimagon/BlackBar

## Requirements

- macOS 13 or later
- Xcode Command Line Tools

## Install

Clone the repository and build the app locally:

```bash
git clone https://github.com/choimagon/BlackBar.git
cd BlackBar
./scripts/package_app.sh
open dist/BlackBar.app
```

If you want a DMG instead:

```bash
./scripts/package_dmg.sh
open dist/BlackBar.dmg
```

## Usage

- Launch `BlackBar.app`
- Click the menu bar icon
- Turn `Top Bar` on or off with the toggle

When `Top Bar` is on, BlackBar tracks the current wallpaper and regenerates the black top bar effect automatically.

## Notes

- Unsigned local builds may show a macOS security warning on some systems
- If needed, open the app with right click -> `Open`
- For clean public distribution on other Macs, the app should be signed and notarized
