#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ==========================================================================
#  tools/build_native.sh - builds the native SubVision 2.0 app for a release
#
#    tools/build_native.sh [--smoke]  ->  dist/SubVision-v<version>-macos-app.zip
#                                         dist/SubVision-v<version>-macos-app.zip.sha256
#
#  --smoke: after the zip, its app is unzipped and its engine launcher started
#  with an empty state folder, twice read-only and once writable (the first
#  launch sets up Python: it needs the network), then the bundle must hold
#  exactly the files of the zip and its signature must still verify.
#
#  Release build with Xcode, then: a copy in a staging folder, a check of
#  everything inside the bundle against an allow-list, an ad hoc signature
#  (no Developer ID), every date of the app set to one fixed time, the zip
#  and its sha256, and at the end a check of the zip itself (unzipped, the
#  signature must hold and every entry must carry the fixed time).
#
#  The engine (the Python program) is embedded by macos/Native/copy_engine.sh
#  during the build; Python itself is downloaded on the first launch.
#
#  Adapted from the build_native.sh of the native macOS app of AnimeUp (by
#  the same author). What differs: the allow-list of the whole bundle, the
#  fixed dates and the final self-check of the zip.
#
#  Needs Xcode (not just the Command Line Tools); xcode-select is left alone,
#  DEVELOPER_DIR points xcodebuild at Xcode for this script only.
# ==========================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DERIVED="$REPO/build/xcode-release"          # Xcode's own derived data
STAGE="$REPO/build/release-stage"            # the copy that gets signed and zipped
DIST="$REPO/dist"
PRODUCT="$DERIVED/Build/Products/Release/SubVision.app"
APP="$STAGE/SubVision.app"

# Every file and folder of the release gets this date (touch -t format, local
# time): Sunday 15 November 2026, 09:56. ZIP_STAMP is how `zipinfo -T` shows it
# (zip entries keep even seconds only).
STAMP="202611150956"
ZIP_STAMP="20261115.095600"

SMOKE=0
for arg in "$@"; do
  case "$arg" in
    --smoke) SMOKE=1 ;;
    *) echo "usage: $0 [--smoke]" >&2; exit 2 ;;
  esac
done

START=$SECONDS
step() { printf '\n==> %s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

[[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || fail "Xcode not found in $DEVELOPER_DIR"

# --------------------------------------------------------------------------
step "1/7 Release build"
# The product is removed first: Xcode copies resources incrementally, so a
# resource deleted from the project would otherwise stay in the old bundle.
rm -rf "$PRODUCT"
# The simulator noise of xcodebuild (CoreSimulator out of date) is filtered;
# PIPESTATUS keeps the exit code of xcodebuild itself.
set +e
xcodebuild -project "$REPO/macos/Native/SubVision.xcodeproj" -scheme SubVision \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" build -quiet 2>&1 \
  | grep -v -E 'CoreSimulator|simulator devices|Simulator device support|IDEMacPlaceholder|^(Domain|Code|Failure Reason|Recovery Suggestion):|^--$|^[[:space:]]*$'
status=${PIPESTATUS[0]}
set -e
[[ $status -eq 0 ]] || fail "xcodebuild failed ($status)"
[[ -d "$PRODUCT" ]] || fail "no app in $PRODUCT"

# --------------------------------------------------------------------------
step "2/7 Copy to the staging folder"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# No resource forks, extended attributes, quarantine or ACLs in the copy.
ditto --norsrc --noextattr --noqtn --noacl "$PRODUCT" "$APP"
find "$APP" \( -name '._*' -o -name '.DS_Store' \) -delete
dot_clean -m "$APP" 2>/dev/null || true
# com.apple.provenance may refuse to go: harmless, the zip leaves xattrs out.
xattr -cr "$APP" 2>/dev/null || true

# --------------------------------------------------------------------------
step "3/7 Check the bundle against the allow-list"
# Each path (relative to the .app) must match one of these patterns; anything
# else stops the build. The engine part mirrors the list of copy_engine.sh,
# and each of its files must also be tracked by git (no stray local files).
ENGINE="Contents/Resources/SubVision"
ALLOW=(
  '^Contents$'
  '^Contents/(Info\.plist|PkgInfo)$'
  '^Contents/MacOS$'
  '^Contents/MacOS/SubVision$'
  '^Contents/_CodeSignature$'
  '^Contents/_CodeSignature/CodeResources$'
  '^Contents/Resources$'
  '^Contents/Resources/(Assets\.car|SubVision\.icns)$'
  '^Contents/Resources/locales$'
  '^Contents/Resources/locales/[a-z]{2}(-[A-Za-z]+)?$'
  '^Contents/Resources/locales/[a-z]{2}(-[A-Za-z]+)?/[a-z_]+\.json$'
  "^$ENGINE\$"
  "^$ENGINE/(subvision|pyproject\\.toml|uv\\.lock|\\.python-version|LICENSE|README\\.md)\$"
  "^$ENGINE/defaults(/[A-Za-z0-9_-]+\\.txt)?\$"
  "^$ENGINE/src(/[A-Za-z0-9_]+)*(\\.py)?\$"
)
# Whatever the patterns say, these never belong in a release.
DENY='(^|/)(__pycache__|\.DS_Store|\._[^/]*|\.git[^/]*|\.venv|\.python|\.cache)(/|$)|\.pyc$'

bad=0
while IFS= read -r path; do
  rel="${path#"$APP"/}"
  ok=0
  for re in "${ALLOW[@]}"; do
    if [[ "$rel" =~ $re ]]; then ok=1; break; fi
  done
  [[ "$rel" =~ $DENY ]] && ok=0
  if [[ -L "$path" ]]; then echo "  symbolic link: $rel" >&2; ok=0; fi
  if [[ $ok -eq 0 ]]; then echo "  not allowed: $rel" >&2; bad=1; continue; fi
  if [[ -f "$path" && "$rel" == "$ENGINE"/* ]]; then
    tracked="${rel#"$ENGINE"/}"
    if [[ -z "$(git -C "$REPO" ls-files -- "$tracked")" ]]; then
      echo "  engine file not tracked by git: $tracked" >&2; bad=1
    fi
  fi
done < <(find "$APP" -mindepth 1 | sort)
[[ $bad -eq 0 ]] || fail "the bundle holds files outside the allow-list"

# What must be there.
for must in Contents/Info.plist Contents/MacOS/SubVision "$ENGINE/subvision" \
            "$ENGINE/pyproject.toml" "$ENGINE/uv.lock" "$ENGINE/README.md" "$ENGINE/LICENSE" \
            "$ENGINE/src/subvision/__init__.py"; do
  [[ -e "$APP/$must" ]] || fail "missing from the bundle: $must"
done
[[ -x "$APP/Contents/MacOS/SubVision" && -x "$APP/$ENGINE/subvision" ]] || fail "executables lost their x bit"
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo "warning: the repository has uncommitted changes; the zip will not match a commit" >&2
fi
echo "  $(find "$APP" -mindepth 1 | wc -l | tr -d ' ') entries, all allowed"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "odd CFBundleShortVersionString: $VERSION"
ZIPNAME="SubVision-v$VERSION-macos-app.zip"
ZIP="$DIST/$ZIPNAME"

# --------------------------------------------------------------------------
step "4/7 Ad hoc signature"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# --------------------------------------------------------------------------
step "5/7 Fixed dates ($STAMP)"
# mtime and atime of every file and folder, the .app included; -h acts on a
# link itself (there are none, the check above refuses them). The signature
# covers contents, not dates, so it still holds afterwards.
find "$APP" -exec touch -h -t "$STAMP" {} +
codesign --verify --deep --strict "$APP"
# Every modification time must now be the fixed one (reading the files, as
# codesign just did, may move access times again; zip entries keep mtime only).
mtimes="$(find "$APP" -exec stat -f '%Sm' -t '%Y%m%d%H%M' {} + | sort -u)"
[[ "$mtimes" == "$STAMP" ]] || fail "dates not normalized: $(echo "$mtimes" | tr '\n' ' ')"

# --------------------------------------------------------------------------
step "6/7 Zip and sha256"
mkdir -p "$DIST"
rm -f "$ZIP" "$ZIP.sha256"
# ditto keeps each file's mtime in its zip entry; no resource forks, xattrs
# or ACLs (so no __MACOSX folder).
(cd "$STAGE" && ditto -c -k --norsrc --noextattr --noacl --keepParent SubVision.app "$ZIP")
(cd "$DIST" && shasum -a 256 "$ZIPNAME" > "$ZIPNAME.sha256")
touch -t "$STAMP" "$ZIP" "$ZIP.sha256"

# --------------------------------------------------------------------------
step "7/7 Self-check of the zip"
CHECK="$(mktemp -d "$REPO/build/zipcheck.XXXXXX")"
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/SubVision.app"
(cd "$DIST" && shasum -a 256 -c "$ZIPNAME.sha256" >/dev/null) || fail "sha256 does not match"

# Same entries as the staged app, nothing more (no __MACOSX, no ._ files).
diff <(zipinfo -1 "$ZIP" | sed 's|/$||' | sort) \
     <(cd "$STAGE" && find SubVision.app | sort) >/dev/null \
  || fail "the zip entries differ from the staged app"

# Every entry carries the fixed time, and no entry falls in working hours
# (weekdays 09:00-12:59 and 14:00-17:59). `zipinfo -T` prints yyyymmdd.hhmmss.
times="$(zipinfo -T "$ZIP" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]{8}\.[0-9]{6}$/) { print $i; break } }')"
entries="$(echo "$times" | grep -c . || true)"
[[ "$entries" -eq "$(zipinfo -1 "$ZIP" | wc -l | tr -d ' ')" ]] \
  || fail "could not read the time of every zip entry ($entries read)"
for ts in $(echo "$times" | sort -u); do
  [[ "$ts" == "$ZIP_STAMP" ]] || fail "zip entry with time $ts instead of $ZIP_STAMP"
  dow="$(date -j -f '%Y%m%d.%H%M%S' "$ts" '+%u')"   # 1 = Monday ... 7 = Sunday
  hhmm="${ts:9:4}"
  if (( dow <= 5 )) && { [[ "$hhmm" > "0859" && "$hhmm" < "1300" ]] || [[ "$hhmm" > "1359" && "$hhmm" < "1800" ]]; }; then
    fail "zip entry time $ts falls in working hours"
  fi
done

# --------------------------------------------------------------------------
if (( SMOKE )); then
  step "Smoke test: nothing written inside the bundle"
  # Nothing may ever be written inside the bundle (a __pycache__ there broke
  # the signature of the installed app). The engine must start from a
  # read-only copy (first launch, then the "environment ready" path); then
  # once more with the copy writable, where a stray write would land, and
  # the files must still be the zip's and the signature must hold.
  SMOKEDIR="$(mktemp -d "$REPO/build/smoke.XXXXXX")"
  trap 'chmod -R u+w "$SMOKEDIR" 2>/dev/null; rm -rf "$CHECK" "$SMOKEDIR"' EXIT
  ditto -x -k "$ZIP" "$SMOKEDIR"
  LAUNCHER="$SMOKEDIR/SubVision.app/Contents/Resources/SubVision/subvision"
  for run in first second third; do
    if [[ $run == third ]]; then chmod -R u+w "$SMOKEDIR/SubVision.app"; else chmod -R a-w "$SMOKEDIR/SubVision.app"; fi
    out="$(SUBVISION_STATO="$SMOKEDIR/state" "$LAUNCHER" --version 2>&1)" \
      || fail "the engine did not start ($run launch): $out"
    [[ "$out" == *"subvision $VERSION"* ]] || fail "unexpected answer of the engine ($run launch): $out"
  done
  diff <(zipinfo -1 "$ZIP" | sed 's|/$||' | sort) \
       <(cd "$SMOKEDIR" && find SubVision.app | sort) \
    || fail "the engine wrote inside the bundle (see the lines above)"
  codesign --verify --deep --strict "$SMOKEDIR/SubVision.app" || fail "the signature broke after a launch"
  echo "  engine started from a read-only bundle and from a writable one; nothing written in it, signature ok"
fi

SIZE="$(stat -f %z "$ZIP")"
SHA="$(cut -d ' ' -f 1 "$ZIP.sha256")"
printf '\nSubVision %s\n' "$VERSION"
printf '  zip     %s\n' "$ZIP"
printf '  size    %s bytes (%s)\n' "$SIZE" "$(du -h "$ZIP" | cut -f 1 | tr -d ' ')"
printf '  sha256  %s\n' "$SHA"
printf '  check   signature ok, %d entries all at %s, none in working hours\n' "$entries" "$ZIP_STAMP"
printf '  time    %ds\n' "$((SECONDS - START))"
