#!/bin/bash
# Regenerates the board PNGs with headless Chrome: one PNG per board and appearance,
# png/<code>-light.png and png/<code>-dark.png, in Italian.
#   LANGS="it en"  also writes the English ones in png/en/
#   PAGES="elabora anteprima"  only those pages
#   BOARDS="E2 A3"  only those boards
# Each page lists its boards and their sizes itself (?list=1 → <pre id="manifest">).
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
LANGS=${LANGS:-it}
PAGES=${PAGES:-"ds strumenti elabora inspector anteprima subfix report impostazioni avvisi stretta"}
BOARDS=${BOARDS:-}
PROFILE=$(mktemp -d "${TMPDIR:-/tmp}/sv-boards.XXXXXX")
trap 'rm -rf "$PROFILE"' EXIT
chrome() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$PROFILE" "$@" </dev/null 2>/dev/null; }

for page in $PAGES; do
  manifest=$(chrome --virtual-time-budget=3000 --dump-dom "file://$PWD/$page.html?list=1" |
    sed -n '/<pre id="manifest">/,/<\/pre>/p' | sed 's/<[^>]*>//g')
  while read -r code w h; do
    [ -z "$code" ] && continue
    if [ -n "$BOARDS" ] && [[ " $BOARDS " != *" $code "* ]]; then continue; fi
    for lang in $LANGS; do
      dir=png; [ "$lang" = it ] || dir=png/$lang
      mkdir -p "$dir"
      for theme in light dark; do
        out="$dir/$code-$theme.png"
        chrome --virtual-time-budget=3000 --window-size="$w,$h" --screenshot="$PWD/$out" \
          "file://$PWD/$page.html?theme=$theme&lang=$lang&board=$code"
        echo "$out  ${w}x$h"
      done
    done
  done <<< "$manifest"
done
