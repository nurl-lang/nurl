#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_package_imports.sh — assert that no package imports
#  itself through a `packages/<name>/…` path.
#
#  Inside this repo every build runs from the repo root, so
#  `$ \`packages/torchpt/src/pickle.nu\`` resolves and every test
#  passes. Installed from the registry the package lands under
#  `deps/<name>/src/`, that path does not exist, and the FIRST thing a
#  consumer sees is:
#
#      nurlc: cannot open 'packages/torchpt/src/pickle.nu'
#
#  torchpt 0.1.0 shipped that way and was uninstallable from the day it
#  was published — no in-repo test can catch it, because in the repo it
#  works. A sibling module is imported by bare filename (`\`pickle.nu\``),
#  which resolves relative to the importing file and is therefore
#  correct in both layouts; a DEPENDENCY is imported through
#  `deps/<pkg>/src/…`, which nurlpkg symlinks in both layouts too.
#
#  Run from the repo root:  ./tools/check_package_imports.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    if [ "$fail" -eq 0 ]; then
        echo "package sources may not import through a 'packages/…' path:" >&2
        echo "(inside the repo it resolves; installed under deps/ it does not)" >&2
        echo >&2
    fi
    echo "  $hit" >&2
    fail=1
done <<EOF
$(grep -rn '^\$ *`packages/' packages/*/src/*.nu packages/*/tests/*.nu 2>/dev/null)
EOF

if [ "$fail" -ne 0 ]; then
    echo >&2
    echo "import a sibling by bare filename ('pickle.nu') and a dependency" >&2
    echo "through 'deps/<pkg>/src/…'." >&2
    exit 1
fi

n=$(ls -d packages/*/ 2>/dev/null | wc -l | tr -d ' ')
echo "package imports OK ($n packages, no 'packages/…' self-imports)"
