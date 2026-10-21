#!/bin/sh
# Build the Romoogle index.
#
# Usage: build-index.sh <roms-dir> <index-file> [progress-file]
#
# Writes an index.json with one item per game:
#   {name, path, search, fuzzy, discs, features.images}
# The expensive walk happens once. Multi-disc .m3u files are canonical; their
# referenced discs are hidden. .cue files hide their referenced tracks. A
# folder with multiple .chd files and no .m3u is grouped and launched from
# disc 1.
set -eu

ROMS_DIR="${1:?usage: build-index.sh <roms-dir> <index-file> [progress-file]}"
INDEX_FILE="${2:?usage: build-index.sh <roms-dir> <index-file> [progress-file]}"
PROGRESS_FILE="${3:-}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
JQ="${JQ:-jq}"

if [ ! -d "$ROMS_DIR" ]; then
    echo "Romoogle: Roms directory not found: $ROMS_DIR" >&2
    exit 1
fi
RESOLVED_ROMS="$(readlink -f "$ROMS_DIR" 2>/dev/null || true)"
if [ -n "$RESOLVED_ROMS" ] && [ -d "$RESOLVED_ROMS" ]; then
    ROMS_DIR="$RESOLVED_ROMS"
fi

INDEX_DIR="${INDEX_FILE%/*}"
[ "$INDEX_DIR" = "$INDEX_FILE" ] && INDEX_DIR="."
mkdir -p "$INDEX_DIR"
META_FILE="${INDEX_DIR}/index.meta"

TMP="${INDEX_FILE}.tmp.$$"
rm -rf "$TMP"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

ROOT_MAP="$ROMS_DIR/map.txt"
SYSTEMS="$TMP/systems"
ALIASES="$TMP/aliases.tsv"
RAW="$TMP/raw.tsv"
HIDE="$TMP/hide.tsv"
: >"$SYSTEMS"
: >"$ALIASES"
: >"$RAW"
: >"$HIDE"

progress() {
    [ -n "$PROGRESS_FILE" ] || return 0
    label="$(printf '%s' "$3" | sed 's/^[0-9][0-9]*) //')"
    tag="$4"
    if [ -n "$tag" ]; then
        case "$label" in
            *"($tag)"*) ;;
            *) label="$label ($tag)" ;;
        esac
    fi
    printf 'Indexing %s of %s %s...' "$1" "$2" "$label" >"$PROGRESS_FILE"
    sleep 0.1
}

emit_raw() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >>"$RAW"
}

find_art() {
    base="$1"
    dir="$2"
    system_dir="$3"
    for candidate in \
        "$dir/.media/$base.png" \
        "$system_dir/.media/$base.png" \
        "$system_dir/.media/${dir##*/}.png" \
        "$dir/Imgs/$base.png" \
        "$system_dir/Imgs/$base.png"
    do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 0
}

find_rom_files() {
    find "$1" \
        \( -type d \( -name '.*' -o -name 'Imgs' \) -prune \) -o \
        \( -type f \
            ! -iname '*.png' \
            ! -iname '*.jpg' \
            ! -iname '*.jpeg' \
            ! -iname '*.webp' \
            ! -iname '*.gif' \
            ! -iname '*.bmp' \
            ! -iname '*.ico' \
            ! -iname '*.svg' \
            ! -iname '*.mid' \
            ! -iname '*.midi' \
            ! -iname '*.lmu' \
            ! -iname '*.ldb' \
            ! -iname '*.lmt' \
            ! -iname '*.dll' \
            ! -iname '*.exe' \
            ! -iname '*.ini' \
            ! -iname '*.lfl' \
            ! -iname '*.gme' \
            ! -iname '*.cpt' \
            ! -iname '*.dnr' \
            ! -iname '*.msg' \
            ! -iname '*.txt' \
            ! -iname '*.log' \
            ! -iname '*.md' \
            ! -iname '*.xml' \
            ! -iname '*.json' \
            ! -iname '*.dat' \
            ! -iname '*.db' \
            ! -iname '*.sqlite' \
            ! -iname '*.sqlite3' \
            ! -iname '*.sav' \
            ! -iname '*.srm' \
            ! -iname '*.state*' \
            ! -iname '*.rtc' \
            ! -iname '*.eep' \
            ! -iname '*.fla' \
            ! -iname '*.sra' \
            ! -iname '*.cfg' \
            ! -iname '*.ini' \
            ! -iname '*.opt' \
            ! -iname '*.cht' \
            ! -iname '*.ips' \
            ! -iname '*.bps' \
            ! -iname '*.ups' \
            ! -iname '*.mp3' \
            ! -iname '*.wav' \
            ! -iname '*.flac' \
            ! -iname '*.ogg' \
            ! -iname '*.m4a' \
            ! -iname '*.mp4' \
            ! -iname '*.mkv' \
            ! -iname '*.avi' \
            ! -iname '*.webm' \
            ! -iname '*.pdf' \
            ! -iname '*.epub' \
            ! -iname '*.mobi' \
            ! -iname '*.html' \
            ! -iname '*.htm' \
            ! -iname '*.css' \
            ! -iname '*.js' \
            ! -iname '*.sh' \
            ! -iname '*.py' \
            -print \
        \)
}

# --- systems, in Roms/map.txt order then alphabetically ---------------------
if [ -f "$ROOT_MAP" ]; then
    while IFS="$(printf '\t')" read -r key value; do
        [ -n "$key" ] || continue
        [ -d "$ROMS_DIR/$key" ] || continue
        printf '%s\n' "$key" >>"$SYSTEMS"
    done <"$ROOT_MAP"
fi
find "$ROMS_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name '.*' ! -name 'Imgs' -print |
    while IFS= read -r dir; do
        printf '%s\n' "${dir##*/}"
    done |
    sort >>"$SYSTEMS"
awk '!seen[$0]++' "$SYSTEMS" >"$SYSTEMS.uniq"
mv "$SYSTEMS.uniq" "$SYSTEMS"

SYSTEM_COUNT="$(wc -l <"$SYSTEMS" | tr -d ' ')"
if [ "$SYSTEM_COUNT" -eq 0 ]; then
    echo "Romoogle: no system folders found under $ROMS_DIR" >&2
    exit 1
fi

# --- per-directory map.txt game aliases -------------------------------------
find "$ROMS_DIR" -name 'map.txt' -print |
    while IFS= read -r map_file; do
        map_dir="${map_file%/*}"
        [ "$map_dir" = "$ROMS_DIR" ] && continue
        while IFS="$(printf '\t')" read -r key value; do
            [ -n "$key" ] || continue
            case "$value" in
                .* | *.disabled) value="__HIDE__" ;;
            esac
            printf '%s\t%s\n' "$map_dir/$key" "$value" >>"$ALIASES"
        done <"$map_file"
    done
# Sentinel so awk's FNR==NR branch is never true for the raw entries file.
printf '__romoogle_none__\t__romoogle_none__\n' >>"$ALIASES"

# --- per-system walk --------------------------------------------------------
system_index=0
while IFS= read -r system; do
    system_index=$((system_index + 1))
    system_dir="$ROMS_DIR/$system"

    tag="$(printf '%s\n' "$system" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
    [ -n "$tag" ] || tag="$system"

    system_alias=""
    if [ -f "$ROOT_MAP" ]; then
        system_alias="$(awk -F '\t' -v k="$system" '$1 == k { print $2; exit }' "$ROOT_MAP")"
    fi
    [ -n "$system_alias" ] || system_alias="$system"
    case "$system_alias" in
        .* | *.disabled) continue ;;
    esac

    progress "$system_index" "$SYSTEM_COUNT" "$system_alias" "$tag"

    ALL="$TMP/all"
    find_rom_files "$system_dir" >"$ALL"

    # .m3u playlists: canonical entries, referenced discs hidden.
    M3U_ENTRIES="$TMP/m3u_entries"
    : >"$M3U_ENTRIES"
    find "$system_dir" -type f -iname '*.m3u' -print >"$TMP/m3us"
    while IFS= read -r m3u; do
        m3u_dir="${m3u%/*}"
        count=0
        disc_count=0
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(printf '%s' "$line" | tr -d '\r')"
            case "$line" in
                '' | '#'*) continue ;;
            esac
            case "$line" in
                /*) disc="$line" ;;
                *) disc="$m3u_dir/$line" ;;
            esac
            case "$line" in
                *.chd|*.CHD|*.cue|*.CUE|*.iso|*.ISO|*.bin|*.BIN|*.img|*.IMG|*.mdf|*.MDF|*.nrg|*.NRG|*.pbp|*.PBP|*.cso|*.CSO|*.gdi|*.GDI|*.cdi|*.CDI)
                    disc_count=$((disc_count + 1)) ;;
            esac
            printf '%s\n' "$disc" >>"$HIDE"
            count=$((count + 1))
        done <"$m3u"
        [ "$count" -gt 0 ] || count=1
        discs=1
        if [ "$disc_count" -eq "$count" ] && [ "$count" -gt 1 ] && [ "$count" -le 16 ]; then
            discs="$count"
        fi
        printf '%s\t%s\n' "$m3u" "$discs" >>"$M3U_ENTRIES"
    done <"$TMP/m3us"

    # .cue files hide their referenced tracks; the cue itself stays an entry.
    find "$system_dir" -type f -iname '*.cue' -print >"$TMP/cues"
    while IFS= read -r cue; do
        cue_dir="${cue%/*}"
        sed -n \
            -e 's/^[[:space:]]*[Ff][Ii][Ll][Ee][[:space:]]*"\(.*\)".*/\1/p' \
            -e 's/^[[:space:]]*[Ff][Ii][Ll][Ee][[:space:]]*\([^"[:space:]].*\)[[:space:]].*/\1/p' \
            "$cue" >"$TMP/tracks"
        while IFS= read -r track; do
            track="$(printf '%s' "$track" | tr -d '\r')"
            [ -n "$track" ] || continue
            case "$track" in
                /*) file="$track" ;;
                *) file="$cue_dir/$track" ;;
            esac
            printf '%s\n' "$file" >>"$HIDE"
        done <"$TMP/tracks"
    done <"$TMP/cues"

    # Folders with multiple CHDs and no m3u: group, launch disc 1.
    GROUP_ENTRIES="$TMP/group_entries"
    : >"$GROUP_ENTRIES"
    find "$system_dir" -type f -iname '*.chd' -print >"$TMP/chds"
    if [ -s "$TMP/chds" ]; then
        sed 's|/[^/]*$||' "$TMP/chds" | sort | uniq -c |
            while read -r count chd_dir; do
                [ "$count" -gt 1 ] || continue
                [ "$chd_dir" = "$system_dir" ] && continue
                if find "$chd_dir" -maxdepth 1 -type f -iname '*.m3u' -print | grep -q .; then
                    continue
                fi
                group_list="$(awk -v d="$chd_dir/" 'index($0, d) == 1' "$TMP/chds" | sort)"
                # Only groups that actually look like disc variants. A folder
                # full of unrelated CHDs (a nested system like Amiga) must not
                # become one "70 discs" game.
                if printf '%s\n' "$group_list" | grep -Eiqv '(disc|disk|cd)[ _-]?[0-9]+'; then
                    continue
                fi
                chosen="$(printf '%s\n' "$group_list" | head -1)"
                [ -n "$chosen" ] || continue
                if grep -Fqx "$chosen" "$HIDE"; then
                    continue
                fi
                # hide every disc, then emit one group entry using disc 1
                printf '%s\n' "$group_list" >>"$HIDE"
                printf '%s\t%s\t%s\n' "$chosen" "$count" "$chd_dir" >>"$GROUP_ENTRIES"
            done
    fi

    # m3u entries
    while IFS="$(printf '\t')" read -r m3u count; do
        display="${m3u##*/}"
        display="${display%.m3u}"
        m3u_dir="${m3u%/*}"
        art="$(find_art "$display" "$m3u_dir" "$system_dir")"
        [ -n "$art" ] || art="$(find_art "${m3u_dir##*/}" "$m3u_dir" "$system_dir")"
        emit_raw "$m3u" "$display" "${m3u##*/}" "$tag" "$system" "$system_alias" "$count" "$art"
    done <"$M3U_ENTRIES"

    # grouped CHD entries
    while IFS="$(printf '\t')" read -r chosen count chd_dir; do
        display="${chd_dir##*/}"
        if [ "$chd_dir" = "$system_dir" ]; then
            display="${chosen##*/}"
            display="${display%.*}"
        fi
        art="$(find_art "$display" "$chd_dir" "$system_dir")"
        [ -n "$art" ] || art="$(find_art "${chosen##*/}" "$chd_dir" "$system_dir")"
        emit_raw "$chosen" "$display" "${chosen##*/}" "$tag" "$system" "$system_alias" "$count" "$art"
    done <"$GROUP_ENTRIES"

    # everything that is not hidden and not an m3u
    if [ -s "$HIDE" ]; then
        grep -Fvx -f "$HIDE" "$ALL" >"$TMP/remaining" || true
    else
        cp "$ALL" "$TMP/remaining"
    fi
    while IFS= read -r path; do
        case "$path" in
            *.m3u | *.M3U) continue ;;
        esac
        name="${path##*/}"
        dir="${path%/*}"
        stem="${name%.*}"
        art="$(find_art "$stem" "$dir" "$system_dir")"
        [ -n "$art" ] || art="$(find_art "${dir##*/}" "$dir" "$system_dir")"
        emit_raw "$path" "$name" "$name" "$tag" "$system" "$system_alias" 1 "$art"
    done <"$TMP/remaining"
done <"$SYSTEMS"

# --- final aliases/search transform and JSON --------------------------------
awk -F '\t' -v OFS='\t' -v roms="$ROMS_DIR" -f "$SCRIPT_DIR/index.awk" "$ALIASES" "$RAW" >"$TMP/final.tsv"
COUNT="$(wc -l <"$TMP/final.tsv" | tr -d ' ')"

"$JQ" -R -s '
    split("\n")[:-1]
    | map(split("\t") | {
        name: .[1],
        path: .[0],
        search: .[2],
        fuzzy: .[3],
        discs: (.[4] | tonumber),
        features: (if (.[5] // "") != "" then {images: {default: .[5]}} else {} end)
      })
    | {items: .}
' <"$TMP/final.tsv" >"$INDEX_FILE.new"
mv "$INDEX_FILE.new" "$INDEX_FILE"

"$JQ" -n --argjson count "$COUNT" --argjson built_at "$(date +%s)" \
    '{count: $count, built_at: $built_at, format: 1}' >"$META_FILE"

if [ -n "$PROGRESS_FILE" ]; then
    printf 'Indexed %s games\n' "$COUNT" >"$PROGRESS_FILE"
fi
