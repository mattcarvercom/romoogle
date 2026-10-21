#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
[ -f "$USERDATA_PATH/$PAK_NAME/debug" ] && set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/$PAK_NAME"

MACHINE="$(uname -m)"
case "$MACHINE" in
    aarch64 | arm64) ARCH=arm64 ;;
    x86_64) ARCH=desktop ;;
    *) ARCH=arm ;;
esac

export HOME="$USERDATA_PATH/$PAK_NAME"
export PATH="$PAK_DIR/bin/$ARCH:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"
JQ="$PAK_DIR/bin/$ARCH/jq"
[ -x "$JQ" ] || JQ="$(command -v jq || true)"
export JQ

LIST_BIN="$PAK_DIR/bin/$PLATFORM/romoogle"
BUILD_SCRIPT="$PAK_DIR/scripts/build-index.sh"
ROMS_DIR="$SDCARD_PATH/Roms"
RESOLVED_ROMS="$(readlink -f "$ROMS_DIR" 2>/dev/null || true)"
if [ -n "$RESOLVED_ROMS" ] && [ -d "$RESOLVED_ROMS" ]; then
    ROMS_DIR="$RESOLVED_ROMS"
fi
INDEX_FILE="$USERDATA_PATH/$PAK_NAME/index.json"
META_FILE="$USERDATA_PATH/$PAK_NAME/index.meta"
STATE_FILE="/tmp/$PAK_NAME-index"
FILTER_FILE="/tmp/$PAK_NAME-filter"
KEYBOARD_STATE_FILE="/tmp/$PAK_NAME-keyboard"
PROGRESS_FILE="/tmp/$PAK_NAME-progress"
DONE_FILE="/tmp/$PAK_NAME-done"
export ROMOOGLE_GAME_LOGS="$SDCARD_PATH/.userdata/shared/game_logs.sqlite"

presenter() {
    command -v minui-presenter 2>/dev/null || true
}

show_message() {
    message="$(printf '%b' "$1")"
    timeout="${2:-2}"
    p="$(presenter)"
    [ -n "$p" ] || { echo "$message"; return 0; }
    killall minui-presenter >/dev/null 2>&1 || true
    if [ "$timeout" = "forever" ]; then
        "$p" --message "$message" --timeout -1 --disable-auto-sleep &
    else
        "$p" --message "$message" --timeout "$timeout" --disable-auto-sleep
    fi
}

cleanup() {
    rm -f /tmp/stay_awake
    killall minui-presenter >/dev/null 2>&1 || true
}

index_count() {
    if [ -f "$META_FILE" ] && [ -n "$JQ" ]; then
        "$JQ" -r '.count // 0' "$META_FILE" 2>/dev/null || echo 0
    elif [ -n "$JQ" ] && [ -f "$INDEX_FILE" ]; then
        "$JQ" '.items | length' "$INDEX_FILE" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

ask_build() {
    p="$(presenter)"
    [ -n "$p" ] || return 0
    message="$(printf '%b' "Build search index?\n\nRomoogle reads the Roms folder once. On a large card this can take a few minutes. After that, searches are instant.")"
    "$p" --message "$message" \
        --confirm-button A --confirm-text SCAN --confirm-show \
        --cancel-button B --cancel-text BACK \
        --timeout 0 --disable-auto-sleep
    rc=$?
    [ "$rc" -eq 0 ]
}

build_index() {
    : >"$PROGRESS_FILE"
    rm -f "$DONE_FILE"
    p="$(presenter)"
    watcher=""
    scan_presenter=""
    if [ -n "$p" ]; then
        if [ "$PLATFORM" = "desktop" ]; then
            # One steady progress window on desktop; restarting the presenter
            # for every system creates a new window for each folder.
            "$p" --message "Scanning Roms..." --timeout -1 --disable-auto-sleep &
            scan_presenter=$!
        else
            "$p" --message "Please wait - scanning Roms..." --timeout -1 --disable-auto-sleep &
            scan_presenter=$!
            (
                last=""
                while [ ! -f "$DONE_FILE" ]; do
                    line="$(cat "$PROGRESS_FILE" 2>/dev/null || true)"
                    if [ -n "$line" ] && [ "$line" != "$last" ]; then
                        last="$line"
                        killall minui-presenter >/dev/null 2>&1 || true
                        "$p" --message "$line" --timeout -1 --disable-auto-sleep &
                    fi
                    sleep 0.1
                done
            ) &
            watcher=$!
        fi
    fi

    if "$BUILD_SCRIPT" "$ROMS_DIR" "$INDEX_FILE" "$PROGRESS_FILE"; then
        : >"$DONE_FILE"
        [ -n "$watcher" ] && kill "$watcher" 2>/dev/null || true
        [ -n "$scan_presenter" ] && kill "$scan_presenter" 2>/dev/null || true
        killall minui-presenter >/dev/null 2>&1 || true
        return 0
    fi

    : >"$DONE_FILE"
    [ -n "$watcher" ] && kill "$watcher" 2>/dev/null || true
    [ -n "$scan_presenter" ] && kill "$scan_presenter" 2>/dev/null || true
    killall minui-presenter >/dev/null 2>&1 || true
    show_message "Index build failed.\nCheck the Romoogle log." 4
    return 1
}

add_game_to_recents() {
    filepath="$1"
    game_alias="$2"
    rel="${filepath#"$ROMS_DIR/"}"
    filepath="Roms/$rel"
    recents="$SDCARD_PATH/.userdata/shared/.minui/recent.txt"
    mkdir -p "$SDCARD_PATH/.userdata/shared/.minui"
    if [ -f "$recents" ]; then
        sed -i "\#/$filepath$(printf '\t')$game_alias#d" "$recents"
    fi
    rm -f "/tmp/recent.txt"
    printf "%s\t%s\n" "/$filepath" "$game_alias" >"/tmp/recent.txt"
    cat "$recents" >>"/tmp/recent.txt" 2>/dev/null || true
    mv "/tmp/recent.txt" "$recents"
}

get_tag() {
    path="$1"
    rel="${path#"$ROMS_DIR/"}"
    system="${rel%%/*}"
    tag="$(printf '%s\n' "$system" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
    [ -n "$tag" ] || tag="$system"
    printf '%s\n' "$tag"
}

get_emu_path() {
    tag="$1"
    for candidate in \
        "$SDCARD_PATH/Emus/$PLATFORM/$tag.pak/launch.sh" \
        "$SDCARD_PATH/.system/$PLATFORM/paks/Emus/$tag.pak/launch.sh"
    do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

launch_game() {
    path="$1"
    idx="$2"
    tag="$(get_tag "$path")"
    emu="$(get_emu_path "$tag" || true)"
    if [ -z "$emu" ]; then
        show_message "No emulator for $tag." 3
        return 1
    fi
    alias=""
    if [ -n "$JQ" ]; then
        alias="$("$JQ" -r --argjson i "$idx" '.items[$i].name // empty' "$INDEX_FILE" 2>/dev/null || true)"
    fi
    alias="$(printf '%s\n' "$alias" | sed -e 's/^\[[^]]*\] //' -e 's/ · [0-9][0-9]* discs$//')"
    [ -n "$alias" ] || alias="${path##*/}"
    add_game_to_recents "$path" "$alias"
    rm -f /tmp/stay_awake
    killall minui-presenter >/dev/null 2>&1 || true
    exec "$emu" "$path"
}

details_screen() {
    idx="$1"
    [ -n "$JQ" ] || return 1
    path="$("$JQ" -r --argjson i "$idx" '.items[$i].path // empty' "$INDEX_FILE" 2>/dev/null || true)"
    [ -n "$path" ] || return 1
    name="$("$JQ" -r --argjson i "$idx" '.items[$i].name // empty' "$INDEX_FILE" 2>/dev/null || true)"
    title="$(printf '%s\n' "$name" | sed -e 's/^\[[^]]*\] //' -e 's/ · [0-9][0-9]* discs$//')"
    tag="$(get_tag "$path")"
    rel="${path#"$ROMS_DIR/"}"
    system="${rel%%/*}"
    discs="$("$JQ" -r --argjson i "$idx" '.items[$i].discs // 1' "$INDEX_FILE" 2>/dev/null || echo 1)"
    art="$("$JQ" -r --argjson i "$idx" '.items[$i].features.images.default // empty' "$INDEX_FILE" 2>/dev/null || true)"

    stem="${path##*/}"
    stem="${stem%.*}"

    save="no"
    if [ -d "$SDCARD_PATH/Saves/$tag" ]; then
        if find "$SDCARD_PATH/Saves/$tag" -maxdepth 2 -type f -iname "${stem}*" -print 2>/dev/null | grep -q .; then
            save="yes"
        fi
    fi

    playtime="n/a"
    playtime_bin="$PAK_DIR/bin/$PLATFORM/romoogle-playtime"
    if [ -x "$playtime_bin" ]; then
        seconds="$("$playtime_bin" "$rel" 2>/dev/null || true)"
        case "$seconds" in
            '' | *[!0-9]*) ;;
            *)
                hours=$((seconds / 3600))
                minutes=$(((seconds % 3600) / 60))
                playtime="${hours}h ${minutes}m"
                ;;
        esac
    fi

    metadata="not fetched"
    meta_file="$USERDATA_PATH/$PAK_NAME/metadata/$(printf '%s' "$rel" | sed 's|/|_|g; s| |_|g').json"
    if [ -f "$meta_file" ] && [ -n "$JQ" ]; then
        metadata="$("$JQ" -r '[.title, .year, .genre] | map(select(. != null and . != "")) | join(" · ")' "$meta_file" 2>/dev/null || true)"
        [ -n "$metadata" ] || metadata="cached"
    fi

    message="$(printf '%s\n%s' "$title" "$system")"
    [ "$discs" -gt 1 ] 2>/dev/null && message="$message · $discs discs"
    message="$(printf '%s\n\nPlaytime: %s\nSave: %s\nMetadata: %s' "$message" "$playtime" "$save" "$metadata")"

    p="$(presenter)"
    if [ -n "$p" ]; then
        killall minui-presenter >/dev/null 2>&1 || true
        if [ -n "$art" ] && [ -f "$art" ]; then
            "$p" --message "$message" --background-image "$art" \
                --cancel-button B --cancel-text BACK --cancel-show \
                --show-pill --disable-auto-wrap \
                --timeout 0 --disable-auto-sleep
        else
            "$p" --message "$message" \
                --cancel-button B --cancel-text BACK --cancel-show \
                --show-pill --disable-auto-wrap \
                --timeout 0 --disable-auto-sleep
        fi
    else
        show_message "$message" 4
    fi
}

run_list() {
    selected="$1"
    keyboard_open="${2:-true}"
    filter=""
    [ -f "$FILTER_FILE" ] && filter="$(cat "$FILTER_FILE")"
    rm -f "$STATE_FILE"

    set -- --file "$INDEX_FILE" --format json --allow-filter true \
        --search-field search --fuzzy-title-field fuzzy --match-mode and --rank \
        --show-filter-count --page-jump --scroll-method pong --filter-button Y \
        --filter-hint --hide-header-on-filter --confirm-text PLAY \
        --action-button SELECT --action-text RESCAN --details-button START \
        --selected-art-background --fuzzy --fuzzy-delay 350 \
        --title "Romoogle" --display-filter-keyboard "$keyboard_open" \
        --filter-input "$filter" \
        --write-value index --write-location "$STATE_FILE" \
        --filter-text-file "$FILTER_FILE" \
        --keyboard-state-file "$KEYBOARD_STATE_FILE" --disable-auto-sleep
    if [ -n "$selected" ] && [ "$selected" -ge 0 ] 2>/dev/null; then
        set -- "$@" --selected "$selected"
    fi
    "$LIST_BIN" "$@"
}

main() {
    echo "1" >/tmp/stay_awake
    trap cleanup EXIT INT TERM HUP

    if [ ! -d "$ROMS_DIR" ]; then
        show_message "No Roms folder found at\n$ROMS_DIR" 4
        return 1
    fi
    if [ ! -x "$LIST_BIN" ]; then
        show_message "Romoogle list binary not found for $PLATFORM." 4
        return 1
    fi

    if [ ! -s "$INDEX_FILE" ]; then
        if ! ask_build; then
            show_message "Romoogle needs an index.\nLaunch it again when ready." 3
            return 0
        fi
        build_index || return 1
        show_message "Indexed $(index_count) games" 2
    fi

    rm -f "$STATE_FILE" "$FILTER_FILE" "$KEYBOARD_STATE_FILE"
    selected=""
    keyboard_open=true
    while true; do
        run_list "$selected" "$keyboard_open"
        rc=$?
        idx="$(cat "$STATE_FILE" 2>/dev/null || true)"
        case "$rc" in
            0)
                [ -n "$idx" ] && [ "$idx" -ge 0 ] 2>/dev/null || { show_message "No game selected." 2; selected=""; continue; }
                path="$("$JQ" -r --argjson i "$idx" '.items[$i].path // empty' "$INDEX_FILE" 2>/dev/null || true)"
                [ -n "$path" ] || { show_message "Could not read the selection." 2; continue; }
                launch_game "$path" "$idx"
                return 0
                ;;
            4)
                p="$(presenter)"
                if [ -n "$p" ]; then
                    message="$(printf '%b' "Rebuild the index?\n\nThis reads the Roms folder again.")"
                    "$p" --message "$message" \
                        --confirm-button A --confirm-text RESCAN --confirm-show \
                        --cancel-button B --cancel-text BACK \
                        --timeout 0 --disable-auto-sleep
                    rebuild_rc=$?
                else
                    rebuild_rc=0
                fi
                if [ "$rebuild_rc" -eq 0 ]; then
                    build_index || true
                    selected="$idx"
                else
                    selected="$idx"
                fi
                ;;
            6)
                details_screen "$idx" || true
                selected="$idx"
                case "$(cat "$KEYBOARD_STATE_FILE" 2>/dev/null || true)" in
                    0) keyboard_open=false ;;
                    *) keyboard_open=true ;;
                esac
                ;;
            2 | 3)
                return 0
                ;;
            *)
                show_message "Romoogle exited with code $rc." 3
                return 1
                ;;
        esac
    done
}

main "$@"
