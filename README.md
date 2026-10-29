# Cellar

Run Windows Steam and games on an Apple Silicon Mac, with a small app to start and stop them.

Cellar builds Wine from the LGPL source code that CodeWeavers publishes for CrossOver, adds its
own patches, and can plug in Apple's D3DMetal for DirectX 11/12. Cellar is an independent
project and is not affiliated with or endorsed by CodeWeavers, Valve or Apple. CrossOver is a
trademark of CodeWeavers, Inc.

## Quick start

```bash
brew install bison mingw-w64 gnutls freetype sdl2
./cellar runtime install staging    # Wine Staging; also supplies x86_64 dylibs for the cx build
./build-wine.sh 26.1.0 cx           # build Wine from CodeWeavers' 26.1 source + patches/
./cellar runtime d3dmetal cx on     # DirectX 11/12 via Apple's D3DMetal
./cellar bottle create steam        # uses the cx runtime by default
./cellar steam install steam
./build-app.sh                      # installs /Applications/Cellar.app
```

Then open **Cellar** from Applications: each bottle shows Running/Stopped with Start/Stop.

`build-wine.sh` cross-compiles x86_64 Wine with Apple clang (runs under Rosetta 2).
It works in `~/.cache/cellar-build` (autoconf can't handle spaces in paths) and installs
the result to `~/Library/Application Support/Cellar/runtimes/cx`. It needs Xcode and ~6 GB free.
If D3DMetal was enabled in that runtime, the rebuild turns it back on.

## Cellar.app

`build-app.sh` compiles `app/CellarApp.swift` (SwiftUI, macOS 14+), bundles a copy of the
`cellar` CLI inside the app, and installs it to `/Applications` (or `~/Applications`).
The app calls `cellar status` every 2 seconds and `cellar steam run` / `cellar kill` for
Start and Stop. Rebuild the app after changing `cellar` so the bundled copy stays current.

## Runtimes

| Name      | Source                            | Notes                                        |
|-----------|-----------------------------------|----------------------------------------------|
| `cx`      | `build-wine.sh` (CodeWeavers 26.1) | Default. Steam UI and sign-in work.          |
| `staging` | Gcenx/macOS_Wine_builds           | Steam login window freezes; dylib donor.     |
| `devel`   | Gcenx/macOS_Wine_builds           | Upstream Wine without staging patches.       |
| `gptk`    | Gcenx/game-porting-toolkit        | DX11/12 via Apple's D3DMetal (Apple license). |

`./cellar runtime link <name> <dir>` registers an existing Wine install as a runtime.

### D3DMetal (DirectX 11/12)

`./cellar runtime d3dmetal cx on` copies Apple's D3DMetal from the `gptk` runtime into `cx`
(downloading `gptk` if needed) and backs up Wine's own DirectX DLLs; `off` restores them.
Without it, Wine's DirectX 11 runs on macOS OpenGL 4.1 and only reaches feature level 10.1,
which many games reject. D3DMetal is covered by Apple's Game Porting Toolkit license, so it
is downloaded on the user's machine and never committed to this repository. Cellar fetches it
from the third-party Gcenx/game-porting-toolkit packaging; by enabling it you are responsible
for accepting Apple's license terms. The official toolkit is available from
[Apple Developer](https://developer.apple.com/games/game-porting-toolkit/).

The D3DMetal `d3d10/d3d11/d3d12/dxgi.so` files must stay symlinks to
`external/libd3dshared.dylib`: separate copies each keep their own state and crash.

## Patches

- `0001-steamwebhelper-in-process-gpu.patch` — Chromium's GPU process draws into windows
  owned by the browser process; winemac.drv can't present cross-process drawing
  (`WND_OTHER_PROCESS` gets no window surface in `win32u/dce.c`), so Steam's UI was black.
  Wine now appends `--in-process-gpu` when starting steamwebhelper's browser process.
  Steam for Windows ignores `-cef-*` launch flags, so this can't be done from `CELLAR_STEAM_ARGS`.
- `0002-neutral-username.patch` — CodeWeavers' source reports every user as `crossover`
  (profile `C:\users\crossover`) instead of the real macOS username. Cellar keeps the privacy
  benefit but uses `cellar`, and renames the built-in "CrossOver" browser entries to "Wine".
  Bottles created before this patch need their `drive_c/users/crossover` folder and registry
  paths renamed, or Steam has to be signed in again.
- `0003-macos-gs-last-error.patch` — Windows code may read the last error straight from
  `%gs:0x68` (TEB.LastErrorValue); Mono's x64 JIT does after every P/Invoke. On macOS `%gs`
  points at the pthread TSD array, where 0x68 is libc's `gmtime()` slot, so Unity games saw
  error 0: `File.Exists` reported missing files as present and Core Keeper never saved
  (`Write failed: Success`). The syscall and unix-call dispatchers now swap that slot at every
  PE/Unix transition, and `SetLastError` also stores to `%gs:0x68`.

## Command line

```bash
./cellar help                       # all commands
./cellar status                     # bottles, runtime, running/stopped
./cellar steam run steam            # start Steam
./cellar kill steam                 # stop everything in the bottle
./cellar open steam                 # open C: drive in Finder
./cellar run steam winecfg          # Wine settings
./cellar steam run steam --hud      # Metal performance HUD
WINEDEBUG=err+all ./cellar steam run steam --fg   # foreground with more logging
```

Data lives in `~/Library/Application Support/Cellar` (override with `CELLAR_HOME`).
Steam's own logs are in `<bottle>/drive_c/Program Files (x86)/Steam/logs`.

## Known issues

- Some games' own Steam Cloud copy step fails ("Write failed: Success"). Workaround: copy
  `Steam/userdata/<id>/<appid>/remote/*` into the game's local save folder.

## License

MIT for the scripts and app; LGPL-2.1-or-later for `patches/` (they modify Wine). See [LICENSE](LICENSE).
