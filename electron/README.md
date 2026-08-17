# Lucky Dangle (Electron)

The same hanging charm as the macOS app, rebuilt on Electron so it runs on
**Windows**, macOS and Linux from one codebase. The physics constants and all
five charm drawings are ported from `../main.swift`, so it should look and swing
the same.

The native macOS build in the parent directory is still the better one to use on
a Mac — it's 400 KB instead of 135 MB. This version exists for Windows.

## Run it from source

```sh
npm install
npm start
```

## Build a Windows package

Both architectures, from any OS:

```sh
npx electron-builder --win --x64 --arm64
```

That writes to `dist/`:

- `Lucky Dangle-1.0.0-win.zip` — Intel/AMD, the one nearly everyone needs
- `Lucky Dangle-1.0.0-arm64-win.zip` — ARM Windows (Surface, Snapdragon laptops)

Each is ~135 MB, because every Electron app ships its own copy of Chromium.

`--win --x64` alone builds only x64. Leaving both flags off builds for whatever
machine you're on, which on an Apple Silicon Mac silently gives you an ARM-only
build that won't start on an ordinary Windows PC.

## Sending it to someone on Windows

Upload the x64 zip to Teams. Tell them:

1. Download and **extract** the zip — don't run it from inside the zip viewer,
   or Windows will launch it from a temp folder and the tray icon may not stick.
2. Run **Lucky Dangle.exe**.
3. SmartScheen will warn that the publisher is unknown. **More info →
   Run anyway.**
4. Nothing appears in the taskbar. Look for the gold **✦** in the system tray,
   near the clock. Right-click it for charms, size, position and quit.

Step 3 is Windows correctly reporting that this `.exe` is unsigned and
unrecognised. It's the same trust question as Gatekeeper on macOS: they are
choosing to trust you, not a certificate authority. Point them at the source
so they can see there's no network access and no dependencies beyond Electron
itself. A code-signing certificate (a few hundred dollars a year) is the only
thing that removes the warning.

## Using it

| Action | What happens |
|---|---|
| Move the mouse around | the charm sways — more when the pointer passes near it |
| Grab the charm and flick | it swings from your throw and settles |
| Click the charm | it drops down for a few seconds, then retracts |
| ⌥⌘L (mac) / Alt+Ctrl+L (Windows) | same drop, from anywhere |
| Tray → Charm | nazar, clover, horseshoe, lucky knot, dog |
| Tray → Size | small / medium / large / huge |
| Tray → Hang it | left / centre / right |
| Tray → Shimmer | turn the glint and sparkles off |

Everywhere except the charm itself the window is click-through, so it never
blocks what's underneath.

Settings are saved to `settings.json` in the app's user-data folder
(`%APPDATA%\Lucky Dangle` on Windows, `~/Library/Application Support/Lucky Dangle`
on macOS).

## How it maps onto the Swift version

| Swift | Here |
|---|---|
| `NSPanel`, borderless, `.statusBar` level | `BrowserWindow` with `transparent`, `frame: false`, always-on-top at `screen-saver` level |
| `ignoresMouseEvents` toggled per frame | renderer reports pointer-on-charm over IPC; main calls `setIgnoreMouseEvents(!hit, { forward: true })` |
| `NSStatusItem` | `Tray` |
| `RegisterEventHotKey` | `globalShortcut` |
| `UserDefaults` | `settings.json` under `app.getPath('userData')` |
| `CGContext`, y-up | canvas 2D, flipped to y-up in `render()` so the drawing code ports verbatim |
| 60 Hz `Timer` | `requestAnimationFrame`, with physics on a fixed 1/60 s step so the feel matches at any refresh rate |

`NSEvent.mouseLocation` has no renderer equivalent while the window is
click-through, so the main process polls `screen.getCursorScreenPoint()` and
forwards it — that's what keeps the charm reacting to the pointer anywhere on
screen.

## Known cosmetic quirks, inherited from the Swift original

- The **lucky knot**'s centre hole shows black: the silhouette is filled solid
  for the drop shadow, and the body then fills `evenodd`, so nothing repaints
  the middle.
- The **clover**'s concave notches pick up some of the shadow's blur.

Both look the same in the macOS build. Fixing them means changing the shared
look on both platforms, so they're left alone here.
