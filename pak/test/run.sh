#!/bin/sh
# Fixture tests for the Romoogle index builder.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

JQ="${JQ:-jq}"
FAILED=0

fail() {
    echo "FAIL: $*" >&2
    FAILED=1
}

check() {
    expression="$1"
    label="$2"
    if "$JQ" -e "$expression" "$INDEX" >/dev/null 2>&1; then
        echo "ok: $label"
    else
        fail "$label"
    fi
}

ROMS="$TMP/Roms"
mkdir -p \
    "$ROMS/Game Boy (GB)/.media" \
    "$ROMS/Sony PlayStation (PS)/Final Fantasy VII (USA)" \
    "$ROMS/Sony PlayStation (PS)/.media" \
    "$ROMS/Sony PlayStation (PS)/Suikoden II (USA)" \
    "$ROMS/Multi (MULTI)/Multi Game" \
    "$ROMS/Cue (CUE)"

printf 'Game Boy (GB)\t001) Game Boy (GB)\nSony PlayStation (PS)\t006) Sony PlayStation (PS)\n' >"$ROMS/map.txt"
: >"$ROMS/Game Boy (GB)/Pokémon Red.gb"
: >"$ROMS/Game Boy (GB)/.media/Pokémon Red.png"
printf 'Pokémon Red.gb\tPokemon Red (alias)\n' >"$ROMS/Game Boy (GB)/map.txt"

: >"$ROMS/Sony PlayStation (PS)/Final Fantasy VII (USA)/Final Fantasy VII (USA) (Disc 1).chd"
: >"$ROMS/Sony PlayStation (PS)/Final Fantasy VII (USA)/Final Fantasy VII (USA) (Disc 2).chd"
: >"$ROMS/Sony PlayStation (PS)/Final Fantasy VII (USA)/Final Fantasy VII (USA) (Disc 3).chd"
printf 'Final Fantasy VII (USA) (Disc 1).chd\nFinal Fantasy VII (USA) (Disc 2).chd\nFinal Fantasy VII (USA) (Disc 3).chd\n' \
    >"$ROMS/Sony PlayStation (PS)/Final Fantasy VII (USA)/Final Fantasy VII (USA).m3u"
: >"$ROMS/Sony PlayStation (PS)/.media/Final Fantasy VII (USA).png"
: >"$ROMS/Sony PlayStation (PS)/Suikoden II (USA)/Suikoden II (USA).chd"

: >"$ROMS/Multi (MULTI)/Multi Game/Multi Game (Disc 1).chd"
: >"$ROMS/Multi (MULTI)/Multi Game/Multi Game (Disc 2).chd"

printf 'FILE "Game.bin" BINARY\n  TRACK 01 MODE2/2352\n' >"$ROMS/Cue (CUE)/Game.cue"
: >"$ROMS/Cue (CUE)/Game.bin"

INDEX="$TMP/index.json"
"$ROOT/scripts/build-index.sh" "$ROMS" "$INDEX"

check '.items | length == 5' 'five game entries'
check '([.items[] | select(.name | startswith("[GB]"))] | length) == 1' 'GB entry exists'
check '([.items[] | select(.name | startswith("[GB]"))][0].name | test("Pokemon Red \\(alias\\)"))' 'map alias becomes display name'
check '([.items[] | select(.name | startswith("[GB]"))][0].search | contains("pokemon"))' 'accent-folded search'
check '([.items[] | select(.name | startswith("[GB]"))][0].search | contains("gb") | not)' 'system tag/extension not searchable'
check '([.items[] | select(.name | startswith("[GB]"))][0].features.images.default | length) > 0' 'GB artwork'
check '([.items[] | select(.name | startswith("[PS]")) | select(.discs == 3)] | length) == 1' 'PS multi-disc entry'
check '([.items[] | select(.name | contains("Final Fantasy VII"))][0].path | endswith(".m3u"))' 'multi-disc launches m3u'
check '([.items[] | select(.path | endswith(".chd")) | select(.name | contains("Final Fantasy VII"))] | length) == 0' 'disc CHDs hidden behind m3u'
check '([.items[] | select(.name | contains("Multi Game"))][0].discs) == 2' 'no-m3u disc group'
check '([.items[] | select(.name | contains("Multi Game"))][0].path | endswith("(Disc 1).chd"))' 'no-m3u group launches disc 1'
check '([.items[] | select(.name | startswith("[CUE]"))][0].name | test("Game.cue"))' 'cue entry'
check '([.items[] | select(.path | endswith(".bin"))] | length) == 0' 'bin track hidden'
check '([.items[] | select(.name | contains("__HIDE__"))] | length) == 0' 'no hidden aliases'
if [ "$("$JQ" -r '.count' "$TMP/index.meta")" = "5" ]; then
    echo "ok: meta count"
else
    fail "meta count"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "All Romoogle index tests passed."
else
    echo "Romoogle index tests failed." >&2
    exit 1
fi
