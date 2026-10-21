# Romoogle pak

Fast indexed ROM search for NextUI/MinUI handhelds.

## What it does

- Builds an index of the `Roms` tree once, then filters it live while you type.
- When the index already exists, opens directly into the three-row mobile-style
  keyboard; `Y` hides it. The header hides while typing so four result rows
  stay visible above the compact keyboard and footer. Until you type, the
  search screen shows a short prompt and the library count instead of results;
  a no-match query shows `No results found`. `B` on an empty query dismisses
  the keyboard.
- Exact matches are ranked first; fuzzy close matches follow below, marked `~`.
- Rows start with the short system tag: `[GBA] Mario Kart ...`. The tag is
  display-only; search does not match system keys like `GB` unless the
  title/filename contains them.
- Only the highlighted game's artwork is drawn, as a dimmed right-side
  background.
- `m3u` multi-disc games are one row and launch the m3u; referenced discs are
  hidden. `.cue` files hide their bins. Multiple CHDs in a folder without an
  m3u are grouped and launched from disc 1.
- `Roms/map.txt` and per-system `map.txt` aliases are searchable and become the
  displayed title.
- `Details` shows local playtime, save status and cached metadata; it never
  fetches from the internet.

## Controls

| Button | Action |
| --- | --- |
| A | Play / type |
| B | Delete / back |
| Y | Show/hide the filter keyboard |
| SELECT | Rescan/rebuild the index |
| START | Details for the selected game |
| ← / → | Previous/next page when the keyboard is hidden |
| L1 / R1 | Previous/next page |
| Menu | Exit |

## Index

The index lives at:

```text
/mnt/SDCARD/.userdata/tg5040/Romoogle/index.json
```

The first launch asks before building it. Press `SELECT RESCAN` on the list to
rescan after adding ROMs, or delete `index.json` and relaunch.

## Build

```sh
make test
make package
```

`make package` writes `dist/Romoogle.pak.zip`. The pak expects the Romoogle list
binary at `bin/tg5040/romoogle`.

## Credits

The list is derived from the MIT-licensed `minui-list`; see the project
`CREDITS.md`. The pak bundles `minui-presenter` (MIT, Jose Diaz-Gonzalez) and
`jq` (MIT, Stephen Dolan and contributors).
