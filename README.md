# Lucky Dangle (local build)

A lucky charm that hangs from the top edge of your Mac's screen. It sways while you
work, ignores every click, and drops in when you call it. Runs entirely on your
machine — no network, no dependencies, no permissions.

## Requirements

macOS 12 or newer and the Xcode command line tools:

```sh
xcode-select --install
```

## Build & run

```sh
cd lucky-dangle
chmod +x build.sh
./build.sh
open build/LuckyDangle.app
```

To keep it: `cp -R build/LuckyDangle.app /Applications/`
To start it at login: System Settings → General → Login Items → **+** → LuckyDangle.

Nothing appears in the Dock. Look for the **✦** in your menu bar.

## Using it

| Action | What happens |
|---|---|
| Move your mouse around | the charm sways — more when the pointer passes near it |
| Grab the charm and flick | it swings from your throw and settles on its own |
| Click the charm | it drops down for a few seconds, then retracts |
| ⌥⌘L | same drop, from anywhere |
| ✦ menu → Charm | nazar, four-leaf clover, horseshoe, lucky knot |
| ✦ menu → Hang it | left / centre / right of the screen |
| ✦ menu → Quit | done |

Everywhere except the charm itself, the window is click-through, so it never
gets in the way of what's underneath — including your menu bar.

## Tweaking it

All the feel is in the `Tuning` block at the top of `main.swift`:

- `restLength` / `dropLength` — how far it hangs, normally and when dropped
- `gravity` — bigger = faster, tighter swing
- `damping` — fraction of swing speed kept per second: `0.9` swings for ages, `0.4` settles quickly
- `mouseDriveNear` — how strongly your pointer stirs it
- `breeze` — set to `0` for a charm that hangs perfectly still when you're idle
- `lengthZeta` — `1` = the drop glides to a stop, `0.6` = it bounces at the bottom
- `charmLag` — lower = the charm swings further behind the cord
- `cordBow` — how much the cord bends as it trails the swing

Animation runs off the display link, so it matches your screen's refresh rate.
Physics integrates at a fixed 240 Hz (`physicsHz`), so the feel is identical
at 60 Hz and 120 Hz.

Rerun `./build.sh` after any change.

## Adding your own charm

1. Add a case to `enum Charm` and give it a `title` and `radius`.
2. Write a `drawX(_ ctx: CGContext, _ r: CGFloat)` that draws centred on `(0,0)`,
   with `+y` pointing up, and hook it into `draw(in:)`.

It'll show up in the menu automatically.

## Notes

The app is unsigned and ad-hoc signed locally, which is fine for something you
compiled yourself — Gatekeeper only questions apps downloaded from the internet.
To uninstall, quit it and delete the `.app`; the only trace left is a small
preferences file you can remove with:

```sh
defaults delete local.luckydangle
```
