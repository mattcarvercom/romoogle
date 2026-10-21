# Romoogle

<p align="center">
  <img src="artwork/romoogle-logo.png" width="760" alt="Romoogle — pixel-art multicolor wordmark on a CRT-style dark banner">
</p>

**Indexed ROM search for NextUI/MinUI handhelds.** One pass over the card, then
live filtering with exact matches, fuzzy close matches, system tags, and
selected-only box art.

Romoogle is its own list application for the MinUI/NextUI platform. The list is
derived from the MIT-licensed `minui-list`; see [CREDITS.md](CREDITS.md).

## Status

**v1.0.0** — initial release for the TrimUI Brick Pro (`tg5040` / NextUI).
Tested on hardware; the ARM build and host-side tests pass.

## Features

- One-time index of `Roms`, then live filtering while typing.
- When the index already exists, opens directly into the three-row mobile-style
  keyboard; `Y` hides it. The header hides while typing so four result rows
  stay visible above the compact keyboard and footer.
- Empty query shows `Start typing to search` plus the library count; a query
  with no matches shows `No results found` with the Romoogle masthead.
- Three-row keyboard with `123` numbers/symbols, a J-shaped space key, and no
  redundant shift/enter keys. `B` on an empty query dismisses the keyboard.
- Short system tag first: `[GBA] Mario Kart ...`. The tag is display-only;
  search does not match system keys like `GB` unless the title/filename contains
  them.
- Exact matches ranked first; fuzzy close matches follow below, marked `~`.
- Multi-token queries highlight every matching token; the selected row scrolls
  long names so the full title is readable.
- Accent folding: `pokemon` finds `Pokémon`.
- Multi-word AND: `gba mario`, `kart mario`.
- `m3u` multi-disc games are one row and launch the m3u; referenced discs are
  hidden. `.cue` hides bins. Multiple CHDs in a folder without an m3u are
  grouped and launched from disc 1.
- `map.txt` aliases are searchable and become the displayed title.
- Selected-only artwork as a dimmed right-side background.
- `SELECT` rescans/rebuilds the index; `START` opens Details with local
  playtime, save status, and cached metadata. No network access.

## Install

1. Copy `Romoogle.pak` (or extract `Romoogle.pak.zip`) into:

   ```text
   /mnt/SDCARD/Tools/tg5040/Romoogle.pak
   ```

   On a host-mounted card that is `Tools/tg5040/Romoogle.pak` from the card
   root.

2. Launch Romoogle from **Tools** on the device.
3. The first launch asks to scan the `Roms` tree. Choose **A SCAN**. Later
   scans/rebuilds can be started with **SELECT RESCAN**.
4. The index is written once; subsequent launches open directly into search.

The index lives at:

```text
/mnt/SDCARD/.userdata/tg5040/Romoogle/index.json
```

## Controls

| Button | Action |
| --- | --- |
| A | Play / type |
| B | Delete / back; dismisses the keyboard when the query is empty |
| Y | Show/hide the filter keyboard |
| SELECT | Rescan/rebuild index |
| START | Details |
| ← / → | Page when the keyboard is hidden |
| L1 / R1 | Page |
| Menu | Exit |

On the keyboard: `123` switches to numbers/symbols, `abc` returns to letters,
and the space key is the two-wide key with the upward arm. There is no shift
because search is case-insensitive, and no enter key because `Y` closes the
keyboard.

## Build

Device (NextUI toolchain):

```sh
make PLATFORM=tg5040-nextui setup
make PLATFORM=tg5040-nextui
```

The device output is `romoogle-tg5040-nextui`; the pak ships it as
`pak/bin/tg5040/romoogle`.

Build and test the pak:

```sh
cd pak
make test
make package
```

`make package` writes `pak/dist/Romoogle.pak.zip`.

## Layout

```text
romoogle/
├── README.md
├── CHANGELOG.md
├── CREDITS.md
├── artwork/               # logo, wordmark, icon
├── romoogle.c             # list app entry point
├── list_*.c / list_*.h    # list modules
├── Makefile
└── pak/                   # NextUI pak
    ├── launch.sh
    ├── scripts/           # index builder + awk transform
    ├── src/               # playtime helper
    └── bin/               # tg5040 binaries + jq + presenter
```

## License and credits

MIT. See [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).
