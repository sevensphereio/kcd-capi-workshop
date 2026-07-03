#!/bin/bash
# tools/switch-lang.sh — toggle the active workshop language by replacing
# root files with symlinks into i18n/<lang>/, with reversible backup of
# the originals to `.lang-stash/from-<active>/`.
#
# Behaviour
# ---------
#   switch-lang.sh fr
#     For every file F present under i18n/fr/, move root/F (if it's a
#     real file) to .lang-stash/from-en/F, then symlink root/F → i18n/fr/F.
#     Files not present under i18n/fr/ are left alone (English fallback).
#
#   switch-lang.sh en
#     Remove every symlink at root that points into i18n/<some>/, then
#     restore originals from .lang-stash/from-en/ (if present).
#
# State
# -----
#   .lang             — name of currently-active language (gitignored)
#   .lang-stash/      — backup of original root files (gitignored)
#
# This is a reversible replacement for the previous `cp`-based script,
# which overwrote root files irreversibly.

set -euo pipefail

LANG="${1:-}"
case "$LANG" in
    en|fr) ;;
    *) echo "Usage: $0 <en|fr>" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STASH="$REPO_ROOT/.lang-stash"

CURRENT="en"
if [ -f "$REPO_ROOT/.lang" ]; then
    CURRENT="$(cat "$REPO_ROOT/.lang")"
fi

# ---------------------------------------------------------------- helpers

# Tear down every symlink at root that points into i18n/.
unlink_all_lang_symlinks() {
    local count=0
    while IFS= read -r -d '' link; do
        local target
        target="$(readlink "$link" || true)"
        if [[ "$target" == *"/i18n/"* ]]; then
            rm -f "$link"
            count=$((count + 1))
        fi
    done < <(find "$REPO_ROOT" \
                -path "$REPO_ROOT/.git"        -prune -o \
                -path "$REPO_ROOT/i18n"        -prune -o \
                -path "$REPO_ROOT/.lang-stash" -prune -o \
                -type l -print0)
    echo "$count"
}

# Restore root files from .lang-stash/from-<lang>/ (if present).
restore_from_stash() {
    local from_dir="$STASH/from-$1"
    if [ ! -d "$from_dir" ]; then
        echo 0; return
    fi
    local count=0
    while IFS= read -r -d '' f; do
        local rel="${f#$from_dir/}"
        local dest="$REPO_ROOT/$rel"
        mkdir -p "$(dirname "$dest")"
        # If a symlink remains at dest, drop it before restoring.
        [ -L "$dest" ] && rm -f "$dest"
        mv "$f" "$dest"
        count=$((count + 1))
    done < <(find "$from_dir" -type f -print0)
    # Clean empty backup tree.
    find "$from_dir" -type d -empty -delete 2>/dev/null || true
    rmdir "$STASH" 2>/dev/null || true
    echo "$count"
}

# ---------------------------------------------------------------- restore to en first

# Always begin from a clean canonical-en state: drop every i18n symlink at
# root and put the stashed en originals back where they belong. The stash
# is keyed on "en" because en is the canonical source — every non-en
# switch backs up the en originals to .lang-stash/from-en/.
unlinked=$(unlink_all_lang_symlinks)
restored=$(restore_from_stash "en")

if [ "$LANG" = "en" ]; then
    rm -f "$REPO_ROOT/.lang"
    echo "Switched to en: removed $unlinked symlinks, restored $restored files from stash."
    exit 0
fi

# ---------------------------------------------------------------- fr (or future) mode

SRC_BASE="$REPO_ROOT/i18n/$LANG"
[ -d "$SRC_BASE" ] || { echo "ERROR: $SRC_BASE does not exist" >&2; exit 1; }

stashed=0
linked=0
while IFS= read -r -d '' src_file; do
    rel="${src_file#$SRC_BASE/}"
    case "$rel" in
        MAPPING.md|README.md|tools/*) continue ;;  # FR-only meta files
    esac
    dest="$REPO_ROOT/$rel"
    mkdir -p "$(dirname "$dest")"
    # Stash the original (real file) before replacing it with a symlink.
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        backup="$STASH/from-en/$rel"
        mkdir -p "$(dirname "$backup")"
        mv "$dest" "$backup"
        stashed=$((stashed + 1))
    elif [ -L "$dest" ]; then
        rm -f "$dest"
    fi
    ln -s "$src_file" "$dest"
    linked=$((linked + 1))
done < <(find "$SRC_BASE" -type f -print0)

echo "$LANG" > "$REPO_ROOT/.lang"
echo "Switched to $LANG: linked $linked files (stashed $stashed originals to .lang-stash/from-en/)."
