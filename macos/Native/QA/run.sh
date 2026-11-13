#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Runs the QA scenarios of the native app (macos/Native/QA/*.txt) against the
# Debug build, through the app's DebugQA commands (SUBVISION_COMMANDS), and
# says which pass. Each scenario gets its own state folder and work folder.
#
#   macos/Native/QA/run.sh [--build] [scenario ...]     (names with or without .txt)
#
# Scenario files, one item per line:
#   # text                a comment
#   @state empty|base     the state folder: empty (a real first launch) or an APFS
#                         clone of the base state (default)
#   @keep-base            when this scenario passes, its state becomes the base
#   @needs <file>         the scenario runs only when $MEDIA/<file> exists (videos of mine that
#                         are not in the repository), else it is skipped
#   @launch               starts the app (the lines before it prepare the folders)
#   @quit                 quits the app and waits for it (done anyway at the end)
#   ! <shell>             runs in bash in $WORK; a non-zero exit fails the scenario
#   <command> [args]      a DebugQA command; its reply is checked by the lines after it:
#   ? <regex>             the reply must match (grep -E)
#   ?! <regex>            the reply must not match
# Variables in commands and shell lines: $ROOT (the worktree), $DEMO (the demo
# clips), $REF (the SRTs of the demo-assets release), $MEDIA (the folder of the
# @needs files), $WORK, $STATE, $OUT.
#
# Environment: SUBVISION_QA_APP (the Debug .app), SUBVISION_QA_BASE (the base
# state; default ~/Library/Application Support/SubVision-qa-base),
# SUBVISION_QA_REF (default: $ROOT/demo/ref, else the scratchpad copy),
# SUBVISION_QA_OUT (where logs and captures go; default a temp folder),
# SUBVISION_QA_MEDIA (the folder of the files that @needs names; unset skips those scenarios).
# UserDefaults are shared with every other instance of the Debug app: each
# scenario sets what it depends on (params, langHint, lang, size) and puts
# the OCR parameters back to the defaults at its end.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APP="${SUBVISION_QA_APP:-$ROOT/build/dd/Build/Products/Debug/SubVision.app}"
BASE="${SUBVISION_QA_BASE:-$HOME/Library/Application Support/SubVision-qa-base}"
DEMO="$ROOT/demo"
REF="${SUBVISION_QA_REF:-$DEMO/ref}"
MEDIA="${SUBVISION_QA_MEDIA:-}"
OUT_ROOT="${SUBVISION_QA_OUT:-$(mktemp -d /tmp/subvision-qa.XXXXXX)}"
REPLY_TIMEOUT="${SUBVISION_QA_TIMEOUT:-1500}"   # seconds a reply may take (the commands have their own waits)

if [[ "${1:-}" == "--build" ]]; then
    shift
    echo "building Debug…"
    xcodebuild -project "$ROOT/macos/Native/SubVision.xcodeproj" -scheme SubVision -configuration Debug \
        -derivedDataPath "$ROOT/build/dd" -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD' | grep -v CoreSimulator || true
fi
[[ -x "$APP/Contents/MacOS/SubVision" ]] || { echo "no Debug app at $APP (run with --build)"; exit 2; }
[[ -f "$DEMO/sintel_ita_hardsub_demo.mp4" ]] || { echo "the demo clips are missing in $DEMO"; exit 2; }

scenarios=()
if (( $# )); then
    for s in "$@"; do s="${s%.txt}"; scenarios+=("$HERE/${s##*/}.txt"); done
else
    while IFS= read -r f; do scenarios+=("$f"); done < <(ls "$HERE"/[0-9]*.txt | sort)
fi

APP_PID=""
FAIL_REASON=""

expand() {   # the scenario's variables in a line
    local s="$1"
    s="${s//\$ROOT/$ROOT}"; s="${s//\$DEMO/$DEMO}"; s="${s//\$REF/$REF}"; s="${s//\$MEDIA/$MEDIA}"
    s="${s//\$WORK/$WORK}"; s="${s//\$STATE/$STATE}"; s="${s//\$OUT/$OUT}"
    printf '%s' "$s"
}

launch() {
    : > "$CMD"; : > "$CMD.out"
    SUBVISION_STATO="$STATE" SUBVISION_CODE="$ROOT" SUBVISION_COMMANDS="$CMD" \
        "$APP/Contents/MacOS/SubVision" > "$OUT/app-stdout.log" 2>&1 &
    APP_PID=$!
}

alive() { [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; }

# Sends one command and waits for its line in <file>.out; the reply goes to REPLY.
send() {
    local before; before=$(wc -l < "$CMD.out" | tr -d ' ')
    printf '%s\n' "$1" >> "$CMD"
    local waited=0
    while (( $(wc -l < "$CMD.out" | tr -d ' ') <= before )); do
        if ! alive; then REPLY="(the app is gone)"; return 1; fi
        if (( waited >= REPLY_TIMEOUT * 4 )); then REPLY="(no reply in ${REPLY_TIMEOUT} s)"; return 1; fi
        sleep 0.25; waited=$((waited + 1))
    done
    REPLY=$(sed -n "$((before + 1))p" "$CMD.out" | cut -f2-)
    return 0
}

quit_app() {
    alive || return 0
    printf 'quit\n' >> "$CMD"
    for _ in $(seq 1 60); do alive || break; sleep 0.25; done
    if alive; then kill "$APP_PID" 2>/dev/null; sleep 1; alive && kill -9 "$APP_PID" 2>/dev/null; fi
    wait "$APP_PID" 2>/dev/null
    APP_PID=""
}

# Nothing of this scenario may survive the app: no engine, no ffmpeg from its state folder.
leftovers() {
    local i
    for i in $(seq 1 20); do
        pgrep -f "$STATE/" > /dev/null || return 0
        sleep 0.5
    done
    pgrep -fl "$STATE/"
    return 1
}

run_scenario() {
    local file="$1" name; name="$(basename "$file" .txt)"
    OUT="$OUT_ROOT/$name"; WORK="$OUT/work"; CMD="$OUT/commands"
    rm -rf "$OUT"; mkdir -p "$WORK"
    local state_kind="base" keep_base=0 line n=0 last_reply="" have_reply=0
    grep -q '^@state empty' "$file" && state_kind="empty"
    grep -q '^@keep-base' "$file" && keep_base=1
    STATE="$OUT/state"
    if [[ "$state_kind" == "base" ]]; then
        [[ -d "$BASE/.venv" ]] || { FAIL_REASON="no base state at $BASE: run 01-first-launch first"; return 1; }
        cp -c -R "$BASE" "$STATE" 2>/dev/null || cp -R "$BASE" "$STATE"
        rm -f "$STATE/records/videos.json" "$STATE/records/app.log" "$STATE/records/engine.log"
    else
        mkdir -p "$STATE"
    fi
    export ROOT DEMO REF MEDIA WORK STATE OUT
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        [[ -z "${line// }" || "$line" == \#* ]] && continue
        case "$line" in
            @state*|@keep-base|@needs*) ;;
            @launch) launch ;;
            @quit) quit_app ;;
            "?! "*)
                (( have_reply )) || { FAIL_REASON="line $n: no reply to check"; return 1; }
                if grep -Eq -- "${line#\?! }" <<< "$last_reply"; then
                    FAIL_REASON="line $n: reply matches «${line#\?! }»: $last_reply"; return 1
                fi ;;
            "? "*)
                (( have_reply )) || { FAIL_REASON="line $n: no reply to check"; return 1; }
                if ! grep -Eq -- "${line#\? }" <<< "$last_reply"; then
                    FAIL_REASON="line $n: reply does not match «${line#\? }»: $last_reply"; return 1
                fi ;;
            "! "*)
                local sh; sh="$(expand "${line#! }")"
                if ! (cd "$WORK" && bash -c "$sh") >> "$OUT/shell.log" 2>&1; then
                    FAIL_REASON="line $n: shell failed: ${line#! }"; return 1
                fi ;;
            *)
                alive || { FAIL_REASON="line $n: the app is not running (missing @launch?)"; return 1; }
                local c; c="$(expand "$line")"
                if ! send "$c"; then FAIL_REASON="line $n: $c → $REPLY"; return 1; fi
                last_reply="$REPLY"; have_reply=1
                printf '  %s\n    → %s\n' "$c" "$REPLY" >> "$OUT/transcript.txt" ;;
        esac
    done < "$file"
    quit_app
    if ! leftovers > "$OUT/leftovers.txt"; then FAIL_REASON="processes left after quitting: $(tr '\n' ' ' < "$OUT/leftovers.txt")"; return 1; fi
    if (( keep_base )); then
        rm -rf "$BASE"; cp -c -R "$STATE" "$BASE" 2>/dev/null || cp -R "$STATE" "$BASE"
        rm -f "$BASE/records/videos.json"
    fi
    return 0
}

passed=0; failed=0; skipped=0; summary=()
for f in "${scenarios[@]}"; do
    [[ -f "$f" ]] || { summary+=("MISSING $(basename "$f")"); failed=$((failed + 1)); continue; }
    name="$(basename "$f" .txt)"
    needs="$(sed -n 's/^@needs //p' "$f" | head -1)"
    if [[ -n "$needs" && ( -z "$MEDIA" || ! -f "$MEDIA/$needs" ) ]]; then
        line="SKIP $name — needs $needs in SUBVISION_QA_MEDIA"
        echo "$line"; summary+=("$line"); skipped=$((skipped + 1)); continue
    fi
    start=$(date +%s)
    FAIL_REASON=""
    if run_scenario "$f"; then
        result="PASS"; passed=$((passed + 1))
    else
        result="FAIL"; failed=$((failed + 1))
        quit_app
        pgrep -f "$STATE/" > /dev/null && pkill -f "$STATE/"
    fi
    secs=$(( $(date +%s) - start ))
    line="$result $name (${secs} s)${FAIL_REASON:+ — $FAIL_REASON}"
    echo "$line"; summary+=("$line")
done
echo
echo "QA: $passed passed, $failed failed, $skipped skipped · logs in $OUT_ROOT"
(( failed == 0 ))
