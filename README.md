# dum-sim

<img src="Resources/AppIcon.png" width="128" alt="A siu mai dumpling in a yellow wrapper">

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

The name is a dim sum joke. Small parcels, delivered.

The menu bar glyph is a bamboo steamer, drawn in code so it stays sharp and works
as a macOS template image. `Resources/AppIcon.png` is the bundle icon, masked into
the macOS icon shape at build time.

## Status

Both halves work: a CLI and a menu bar app you can drop files onto.

## Install

Requires Xcode 27 or later. Build it, then put the binary on your `PATH`.

```sh
git clone https://github.com/ricsantos/dum-sim.git
cd dum-sim
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/dum-sim ~/.local/bin/
```

Check that `~/.local/bin` is on your `PATH`:

```sh
echo $PATH | tr ':' '\n' | grep '\.local/bin' || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

`/usr/local/bin` works too, but it belongs to root and needs `sudo`.

### Update after a change

```sh
swift build -c release && cp .build/release/dum-sim ~/.local/bin/
```

### Install the menu bar app

`DumSim.app` puts the drop target back. It carries the CLI inside it.

```sh
make install          # ~/.local/bin/dum-sim and /Applications/DumSim.app
open /Applications/DumSim.app
```

Or build the bundle alone:

```sh
make app              # build/DumSim.app
```

A Homebrew cask arrives once the app is notarised.

## Menu bar app

Drop files on the menu bar icon. That is the whole workflow.

The icon shows a popover with the result, then closes itself. Click the icon for
a menu:

| Item | Meaning |
| --- | --- |
| Target Simulator | Pin a device, or follow whichever one is booted. |
| Destination | Automatic, always Photos, or always Files. |
| Open Destination After Drop | Bring Photos or Files to the front after a copy. |
| Keep Drop Window On Screen | Leave the floating panel visible. |
| Show Drop Window While Dragging | Let the panel appear by itself during a drag. |
| Move Drop Window Under Icon | Put the panel back below the menu bar icon. |
| Copy Files... | A file panel, for when dragging is awkward. |

The app has no dock icon and no window of its own. It is an `LSUIElement` agent.

### The drop window

macOS reads a drag to the top edge of the screen as a Spaces gesture, which makes
the menu bar icon an awkward target. So the app also has a floating panel.

1. Start dragging a file. The panel appears under the menu bar icon.
2. Drop the file on the panel.
3. The panel disappears again.

Drag the panel anywhere you like and it stays there. "Move Drop Window Under Icon"
returns it to the icon.

The panel floats above full screen apps and joins every Space.

### More than one simulator booted

The panel grows into a picker. Each booted simulator gets a card with a live
screenshot, so you can tell an iPhone from an iPad at a glance. Click a card to
copy there. Tick "Remember" to pin that device and skip the picker next time.

The CLI reports the ambiguity instead, and lists the UDIDs to choose from.

## CLI usage

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

## Credits

The Files app container route comes from
[mnem on the Apple Developer Forums](https://developer.apple.com/forums/thread/846994).

## Licence

MIT.

Not affiliated with Apple. Apple, Xcode, iOS, iPhone and iPad are trademarks of
Apple Inc.
