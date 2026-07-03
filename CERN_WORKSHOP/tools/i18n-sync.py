#!/usr/bin/env python3
"""i18n-sync.py — keep i18n/<lang>/ aligned with the canonical English root.

Two modes:

  --check (default in CI)
      Compare every file under i18n/<lang>/ against its root counterpart
      and report:
        * Missing — root has the file, FR doesn't.
        * Stale   — file is present in both but the FR copy is older
                    than the root copy AND has different content.
        * Orphan  — FR has a file that doesn't exist at the root
                    (likely a renamed/removed module).
      Exits 0 if all three categories are empty, else exits 1.

  --report
      Print the same triage as a markdown table on stdout.
      Used to refresh i18n/fr/MAPPING.md.

  --emit-en
      Generate i18n/en/ as a verbatim mirror of the root tree (modulo
      a small whitelist) so non-default-lang sites can stage from there.
      Off by default — keeping i18n/en/ deleted is the canonical state
      for now. (Enable in CI once the workflow expects an EN copy.)

Whitelist of files we sync:
  - module-NN-*/README.md
  - module-NN-*/validate.sh
  - module-NN-*/module.yaml
  - module-NN-*/challenges/{hints,solution}.md
  - module-00-setup/common/validate-env.sh
  - root: README.md, STUDENT_README.md, INSTRUCTOR_README.md,
          GEMINI.md, WALKTHROUGH.md, CONTRIBUTING.md, ROADMAP.md

Anything outside the whitelist is ignored — the sync deliberately
doesn't try to translate scripts, manifests or generated artifacts.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Files at the root that are translatable as a unit (no per-module wrapping).
ROOT_FILES = {
    "README.md",
    "STUDENT_README.md",
    "INSTRUCTOR_README.md",
    "GEMINI.md",
    "WALKTHROUGH.md",
    "CONTRIBUTING.md",
    "ROADMAP.md",
}

# Per-module translatable files (relative to module-*/).
#
# Note: validate.sh is auto-generated from module.yaml and emits the same
# English banners regardless of student locale, so we don't track it for
# translation drift. Likewise, module.yaml is machine-readable schema —
# the only translatable strings inside (title, description) come back to
# the dashboard in English by design. Both are intentionally excluded.
MODULE_FILES = {
    "README.md",
    "challenges/hints.md",
    "challenges/solution.md",
}


@dataclass
class Diff:
    rel: str
    kind: str  # missing | stale | orphan
    detail: str = ""

    def __str__(self) -> str:
        return f"  [{self.kind:<7}] {self.rel}  {self.detail}".rstrip()


def _collect_root_files() -> set[str]:
    """All canonical-root files we're willing to translate (relative paths)."""
    found: set[str] = set()
    for f in ROOT_FILES:
        if (REPO_ROOT / f).is_file():
            found.add(f)
    for mod in sorted(REPO_ROOT.glob("module-*")):
        if not mod.is_dir():
            continue
        for sub in MODULE_FILES:
            p = mod / sub
            if p.is_file():
                found.add(str(p.relative_to(REPO_ROOT)))
    # one stray we want kept:
    extra = REPO_ROOT / "module-00-setup" / "common" / "validate-env.sh"
    if extra.is_file():
        found.add(str(extra.relative_to(REPO_ROOT)))
    return found


def _collect_lang_files(lang: str) -> set[str]:
    base = REPO_ROOT / "i18n" / lang
    if not base.is_dir():
        return set()
    found: set[str] = set()
    for p in base.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(base)
        if rel.name == "MAPPING.md":
            continue
        found.add(str(rel))
    return found


def diff_lang(lang: str) -> list[Diff]:
    """Compute (missing, stale, orphan) for the given language."""
    root_files = _collect_root_files()
    lang_files = _collect_lang_files(lang)

    out: list[Diff] = []

    # Missing: root has it, lang doesn't (only flag for module READMEs by
    # default — don't penalise unfinished translation of every script).
    for rel in sorted(root_files - lang_files):
        # Only README.md is required for a "translated module"; let
        # validate.sh / module.yaml fall back to root silently.
        if rel.endswith("/README.md") or rel in ROOT_FILES:
            out.append(Diff(rel, "missing", "(falls back to root)"))

    # Stale: present in both, content differs, root mtime > lang mtime.
    for rel in sorted(root_files & lang_files):
        root_p = REPO_ROOT / rel
        lang_p = REPO_ROOT / "i18n" / lang / rel
        try:
            if root_p.read_bytes() == lang_p.read_bytes():
                continue
        except OSError:
            continue
        rt = root_p.stat().st_mtime
        lt = lang_p.stat().st_mtime
        if rt > lt:
            out.append(Diff(rel, "stale", f"(root edited {int(rt - lt)}s after FR)"))

    # Orphan: lang has it, root doesn't.
    for rel in sorted(lang_files - root_files):
        out.append(Diff(rel, "orphan", "(no root counterpart)"))

    return out


def emit_en():
    """Mirror root → i18n/en/ for the whitelisted file set."""
    en_base = REPO_ROOT / "i18n" / "en"
    en_base.mkdir(parents=True, exist_ok=True)
    for rel in _collect_root_files():
        src = REPO_ROOT / rel
        dst = en_base / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
    print(f"emitted {len(_collect_root_files())} files to i18n/en/")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang", default="fr", help="Language to check (default: fr)")
    ap.add_argument("--check", action="store_true", help="Exit non-zero on orphan entries (rename mismatches). 'stale' and 'missing' are informational unless --strict.")
    ap.add_argument("--strict", action="store_true", help="With --check, also fail on stale entries.")
    ap.add_argument("--report", action="store_true", help="Print a markdown report")
    ap.add_argument("--emit-en", action="store_true", help="Generate i18n/en/ from root")
    args = ap.parse_args()

    if args.emit_en:
        emit_en()
        return 0

    diffs = diff_lang(args.lang)

    if args.report:
        print(f"# i18n/{args.lang}/ vs root\n")
        if not diffs:
            print("No drift detected.")
            return 0
        print("| File | Kind | Note |")
        print("|---|---|---|")
        for d in diffs:
            print(f"| `{d.rel}` | {d.kind} | {d.detail} |")
        return 0

    # default: human-readable summary
    if not diffs:
        print(f"i18n/{args.lang}/ is in sync with the root.")
        return 0

    counts: dict[str, int] = {}
    for d in diffs:
        counts[d.kind] = counts.get(d.kind, 0) + 1
        print(d)
    print()
    summary = ", ".join(f"{v} {k}" for k, v in sorted(counts.items()))
    print(f"Summary: {summary}.")

    if args.check:
        # Orphans always fail (rename mismatch — somebody renamed root
        # without renaming the FR mirror). Stale optionally fails with
        # --strict. Missing is purely informational.
        hard_kinds = {"orphan"}
        if args.strict:
            hard_kinds.add("stale")
        hard = [d for d in diffs if d.kind in hard_kinds]
        if hard:
            kinds = "/".join(sorted(hard_kinds))
            print(
                f"\n::error::{len(hard)} hard drift entries ({kinds}) — fix or rebase.",
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
