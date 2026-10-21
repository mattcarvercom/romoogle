# Changelog

## 1.0.0 — 2026-10-20

Initial Romoogle release for the TrimUI Brick Pro (`tg5040` / NextUI).

- One-pass indexed search across the `Roms` tree.
- Live exact filtering with prefix ranking, fuzzy close matches, accent
  folding, and multi-word AND matching.
- Short system tags, `map.txt` aliases, multi-disc `m3u` handling, `.cue`
  filtering, and conservative no-m3u disc grouping.
- Selected-only artwork, local playtime, save status, and cached metadata in
  Details.
- Mobile three-row keyboard with `123`/`abc`, J-shaped space, live counts,
  no-results and empty-search states.
- Index scanning, progress, and rescan confirmation for NextUI. The device
  shows a `Please wait - scanning Roms...` window while the first pass starts,
  then clean `Indexing N of Y Name (TAG)...` progress.
- System tags are display-only; search does not match `GB` from `[GB]` unless
  the title/filename contains it.
- Retro PC asset/data files are skipped during indexing, so the scan only
  considers game files.
- Multi-word queries highlight every matching word token and rank the first
  query token more strongly; selected long titles scroll instead of ending in
  an ellipsis.
- Device progress messages are held for at least ~100 ms so fast systems do
  not disappear between updates.
- Added pixel-art artwork: a CRT banner, transparent wordmark, and square icon
  using the multicolor search-wordmark palette.
- The `p` key moves down to the J-shaped space key; space moves back up to `p`.
- First-run and rebuild prompts use real newlines, `B BACK` / `A SCAN` or
  `A RESCAN`.
