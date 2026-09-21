# dum-sim

Drag and drop is gone from the iOS simulator. Xcode 27 replaced Simulator.app with
Device Hub, and Device Hub does not accept a file dropped from Finder
([FB23368633](https://developer.apple.com/forums/thread/846994)).

`dum-sim` puts that workflow back. Give it files, it puts them in the right place
on the simulator.

```
dum-sim ~/Downloads/screenshot.png      # -> Photos
dum-sim ~/Downloads/backup.sqlite       # -> Files, "On My iPhone"
dum-sim --app com.example.App seed.json # -> that app's Documents folder
```

## Status

Stage 1 of 2. The CLI works. A menu bar drop target is next.

## Install

Requires Xcode 27 or later.

```sh
git clone https://github.com/ricsantos/dum-sim.git
cd dum-sim
swift build -c release
cp .build/release/dum-sim /usr/local/bin/
```

## Usage

```
dum-sim [options] <file>...      Copy files into a simulator.
dum-sim devices                  List available simulators.
dum-sim --help                   Show the usage text.
```

| Option | Meaning |
| --- | --- |
| `-d, --device <name\|udid>` | Target simulator. Default: the booted one. |
| `-t, --to <where>` | Force a destination: `photos`, `files`, or `app`. |
| `--app <bundle-id>` | App container to copy into. Implies `--to app`. |
| `--path <subpath>` | Subpath inside the app container. Default: `Documents`. |
| `-o, --open` | Launch the destination app after the copy. |
| `-q, --quiet` | Print nothing on success. |

### Routing

`dum-sim` picks a destination from the file extension.

1. Images, videos and vCards go to the Photos library.
2. Everything else goes to "On My iPhone" in the Files app.
3. A file that Photos refuses falls back to Files.

Pass `--to` to override the choice.

### Examples

```sh
dum-sim ~/Pictures/*.heic                          # bulk import photos
dum-sim -d "iPhone 17 Pro" -o receipt.pdf          # pick a device, then open Files
dum-sim --to files export.csv                      # force Files
dum-sim --app com.example.App --path Library/Caches warm.bin
```

A name collision is not an overwrite. `report.pdf` becomes `report 2.pdf`.

## How it works

Three mechanisms, no private API.

**Photos.** `xcrun simctl addmedia <udid> <paths>`. One call per batch, so a live
photo pair (`.heic` plus `.mov`) imports as one live photo.

**Files.** The Files app stores "On My iPhone" in an app group container:

```sh
xcrun simctl get_app_container <udid> com.apple.DocumentsApp groups
```

The group is `group.com.apple.FileProvider.LocalStorage`, and the visible folder is
`File Provider Storage` inside it. `dum-sim` copies to a hidden temporary name in
that folder, then renames the file into place. The rename is atomic. A plain `cp`
can leave a zero byte file, because the file provider sometimes reads the file while
the copy is still running.

**App container.** `xcrun simctl get_app_container <udid> <bundle-id> data`, then
the subpath.

## Roadmap

1. CLI. Done.
2. Menu bar app with a drop target. A drop copies the files to the booted simulator.
3. A floating window that follows the simulator, for people who want a visible target.
4. A Finder "Share with simulator" extension, if the menu bar app is not enough.

## Credits

The Files app container route comes from
[mnem on the Apple Developer Forums](https://developer.apple.com/forums/thread/846994).

## Licence

MIT.
