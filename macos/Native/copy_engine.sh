#!/usr/bin/env bash
# Copies the engine (the Python program) into the app bundle:
# Contents/Resources/SubVision/ gets an allow-list of the repository, nothing
# else: the launcher, the project files uv needs, the sources and the
# starter lists. Python itself is not bundled: the launcher downloads it with
# uv on the first launch, into the state folder.
#
# Adapted from the copy_engine.sh of the native macOS app of AnimeUp (by the
# same author), which used a block-list; here the list says what goes in, so
# a new folder in the repository never ends up in the bundle by mistake.
#
# Debug builds skip this: the scheme sets SUBVISION_CODE to the worktree, so a
# Python change needs no rebuild. EMBED_ENGINE=YES forces the copy.
set -euo pipefail

if [[ "${CONFIGURATION:-Debug}" == "Debug" && "${EMBED_ENGINE:-NO}" != "YES" ]]; then
  echo "Debug: engine not embedded (runs from \$SUBVISION_CODE)"
  exit 0
fi

REPO="$(cd "${SRCROOT}/../.." && pwd)"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/SubVision"

# What the engine is made of. Folders are copied whole, minus caches.
# README.md and LICENSE are there because pyproject.toml names them: uv
# builds the project on the first launch and hatchling refuses without them.
ALLOW=(subvision pyproject.toml uv.lock .python-version LICENSE README.md src defaults)

rm -rf "$DEST"
mkdir -p "$DEST"
for item in "${ALLOW[@]}"; do
  if [[ ! -e "$REPO/$item" ]]; then
    echo "error: $item is missing from the repository" >&2
    exit 1
  fi
  if [[ -d "$REPO/$item" ]]; then
    mkdir -p "$DEST/$item"
    (cd "$REPO/$item" && tar --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' -cf - .) | tar -xf - -C "$DEST/$item"
  else
    cp "$REPO/$item" "$DEST/$item"
  fi
done
chmod +x "$DEST/subvision"

# Nothing outside the list may have slipped in.
while IFS= read -r entry; do
  name="${entry#./}"
  top="${name%%/*}"
  if [[ ! " ${ALLOW[*]} " == *" $top "* ]]; then
    echo "error: $name is not in the engine's allow-list" >&2
    exit 1
  fi
done < <(cd "$DEST" && find . -mindepth 1 -maxdepth 1)
echo "engine copied to $DEST"
