# Sourced, not run. Needs $ROOT; leaves a Python that can build and read disk
# images in $DMG_PYTHON, and dmgbuild beside it in $DMG_BUILD.
#
# A virtualenv under .build rather than whichever Python this machine happens
# to have things installed into, so neither the image nor the check that reads
# it back changes with the state of a developer's home directory. The version
# is pinned for the same reason: dmgbuild owns the .DS_Store byte layout and
# the exact WindowBounds string check-dmg.sh matches on, so an unpinned
# install would hand the artefact over to whatever PyPI served that morning.
#
# The probe is an import rather than a test for the file, because the venv's
# python is a symlink into a framework that a Python upgrade can remove. That
# leaves an executable bin/dmgbuild whose interpreter no longer exists — a
# state a file test calls healthy and every later command fails on.
DMG_TOOLS="$ROOT/.build/dmgtools"
DMG_PYTHON="$DMG_TOOLS/bin/python"
DMG_BUILD="$DMG_TOOLS/bin/dmgbuild"
DMG_VERSION="1.6.7"

if ! "$DMG_PYTHON" -c "import dmgbuild, ds_store" >/dev/null 2>&1; then
    echo "installing dmgbuild $DMG_VERSION into .build/dmgtools…"
    rm -rf "$DMG_TOOLS"
    python3 -m venv "$DMG_TOOLS" \
        && "$DMG_TOOLS/bin/pip" install --quiet --disable-pip-version-check \
               "dmgbuild==$DMG_VERSION" \
        || { echo "could not install dmgbuild — check python3 and the network" >&2
             return 1; }
fi
