"""
Command-line entry point (`subvision`).

Placeholder: the real sub-commands (extract, fix, preview, serve) arrive
with the launcher in F1.9. For now the script exists and prints the version,
so `[project.scripts]` resolves and the package can be installed and tested.
"""

from __future__ import annotations

import sys

from subvision import __version__


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if args and args[0] not in ("--version", "-V"):
        print(f"subvision {__version__}: command '{args[0]}' not available yet",
              file=sys.stderr)
        return 2
    print(f"subvision {__version__}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
