# Engine tests

The engine is developed in a self-contained environment: uv 0.11.4 (the
version the launcher pins) and the CPython 3.13.12 it downloads, under
`~/Library/Application Support/SubVision-dev`. No system Python, no Homebrew uv.

```sh
DEV="$HOME/Library/Application Support/SubVision-dev"
mkdir -p "$DEV/bin"
curl -sSL -o /tmp/uv.tar.gz \
  https://github.com/astral-sh/uv/releases/download/0.11.4/uv-aarch64-apple-darwin.tar.gz
echo "9b9cb6c6f58c3246dbf3351ed4e97c500bc3266f5f237d2fd620b66e1c31dc56  /tmp/uv.tar.gz" | shasum -a 256 -c -
tar xzf /tmp/uv.tar.gz -C /tmp && cp /tmp/uv-aarch64-apple-darwin/uv "$DEV/bin/uv"

export UV_PYTHON_INSTALL_DIR="$DEV/.python"
export UV_CACHE_DIR="$DEV/.cache/uv"
export UV_PROJECT_ENVIRONMENT="$DEV/.venv"
export UV_PYTHON_DOWNLOADS=automatic
export UV_PYTHON_PREFERENCE=only-managed

"$DEV/bin/uv" sync --frozen          # engine + dev group (pytest)
"$DEV/bin/uv" run pytest             # or: "$DEV/.venv/bin/python" -m pytest
```

`uv lock` (after a dependency change) runs with the same uv and variables.

The launcher `./subvision` does the same for a user: uv 0.11.4 and Python
go into `$SUBVISION_STATO` (default `~/Library/Application Support/SubVision`),
`uv sync --frozen` runs only when `.venv/.subvision-lock-sha256` differs
from the sha256 of `uv.lock`. `SUBVISION_LAUNCHER_CHECK=1` makes it print
its decision ("environment ready" / "sync needed") and exit, which is what
`tests/test_cli.py` uses to test it without network. The sidecar and the
CLI take the ffmpeg of the tests from `SUBVISION_FFMPEG` (set by the test
helpers from the `ffmpeg_bin` fixture).

The demo clips (`demo/sintel_ita_hardsub_demo.mp4`, `demo/sintel_eng_hardsub_demo.mp4`,
from the `demo-assets` release) are expected in `demo/` at the repo root; tests
that need them skip when they are missing. ffmpeg/ffprobe come from `PATH` or
`/opt/homebrew/bin`. The full run on the ita clip takes ~10 s from the second
time; the very first Vision call on a Mac can take ~30 s.

## Damaged videos

Two repeatable recipes on a demo clip (`damage_head` / `damage_tail` in
`conftest.py`, used by `test_batch.py` and `test_serve.py`; the same commands
make the files for the "corrupted video" QA scenario of the app):

```sh
SRC=demo/sintel_ita_hardsub_demo.mp4
# (a) refused by videos.probe: no index ("moov atom not found")
tail -c +100001 "$SRC" > no-index.mp4
# (b) accepted by the probe (55 s, 1280x544), fails in the middle of the
#     extraction: the first MB of the clip, then zeros up to the same size
{ head -c 1000000 "$SRC"; head -c $(( $(stat -f%z "$SRC") - 1000000 )) /dev/zero; } > damaged.mp4
```

(b) fails because ffmpeg gives up when more than 2/3 of the frames cannot be
decoded (`batch.file.failed`, code `unknown`, tool `ffmpeg`, at
`extract:bottom`). With less damage (zeros from the middle on, or a truncated
file) ffmpeg ends well and the file is `done` with a shorter SRT.
