#!/usr/bin/env python3
"""capi-author.py — Module authoring CLI for the CAPI Workshop.

Subcommands:
    new         Scaffold a new module (interactive wizard or --from-yaml)
    validate    Validate module.yaml schema + content integrity
    generate    Generate validate.sh from module.yaml (wraps generate-validation.py)
    migrate     Reverse-engineer module.yaml from existing validate.sh
    list        List all modules with metadata
    check-types List all available validation check types

Usage:
    python3 tools/capi-author.py new my-module
    python3 tools/capi-author.py validate --all
    python3 tools/capi-author.py generate module-07-observability --diff
    python3 tools/capi-author.py migrate --all --dry-run
    python3 tools/capi-author.py list
    python3 tools/capi-author.py check-types
"""
import argparse
import os
import re
import stat
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("ERROR: pyyaml is required. Install with: pip install pyyaml")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_schema import (
    CHECK_TYPES, ValidationError, get_extended_check_types,
    validate_module, validate_all_modules,
)
import importlib
_gen_mod = importlib.import_module("generate-validation")
gen_module = _gen_mod.generate_module

REPO_ROOT = Path(__file__).resolve().parent.parent

# --- Templates ---

README_TEMPLATE = """\
# Module {order:02d}: {title}

## Objectives
- [ ] TODO: Define learning objectives

## Prerequisites
{prerequisites_list}

## Instructions

### Step 1: TODO

Describe the first step here.

## Validation

```bash
./validate.sh
```

## Dig Deeper Challenge

TODO: Define challenge

Need help? Run:

```bash
~/request-help.sh {dir_name}
```
"""

MODULE_YAML_TEMPLATE = """\
# Module metadata — see CONTRIBUTING.md for full schema reference
title: "{title}"
order: {order}
difficulty: {difficulty}
estimated_minutes: {estimated_minutes}
description: "{description}"
prerequisites: {prerequisites}
tags: {tags}

# Validation checks — use 'checks' for simple mode or 'stages' for progressive mode
# Available check types: {check_types}
#
# Simple mode example:
# checks:
#   - name: "kubectl installed"
#     type: tool_exists
#     tool: kubectl
#
# Staged mode example:
# stages:
#   - name: "Prerequisites"
#     on_fail: pending
#     checks:
#       - name: "kubectl installed"
#         type: tool_exists
#         tool: kubectl
#   - name: "Cluster Ready"
#     on_fail: in_progress
#     checks:
#       - name: "Pods running"
#         type: pods_running
#         namespace: default
#         min_count: 1
{validation_block}
"""

HINTS_TEMPLATE = """\
# Hints for Module {order:02d}: {title}

## Challenge 1

**Hint:** TODO: Add hint for challenge 1

## Challenge 2

**Hint:** TODO: Add hint for challenge 2
"""

SOLUTION_TEMPLATE = """\
# Solution for Module {order:02d}: {title}

## Challenge 1

TODO: Add solution for challenge 1

## Challenge 2

TODO: Add solution for challenge 2
"""


# --- Helpers ---

def _discover_modules():
    """Discover all module directories and return sorted list of (dir_name, meta_or_None)."""
    modules = []
    for mod_dir in sorted(REPO_ROOT.glob("module-*")):
        if mod_dir.name.startswith("module-00"):
            continue
        yaml_path = mod_dir / "module.yaml"
        meta = None
        if yaml_path.exists():
            try:
                with open(yaml_path) as f:
                    meta = yaml.safe_load(f) or {}
            except Exception:
                pass
        modules.append((mod_dir.name, meta))
    return modules


def _next_order():
    """Find the next available order number."""
    max_order = 0
    for _, meta in _discover_modules():
        if meta:
            max_order = max(max_order, meta.get("order", 0))
        else:
            # Try to extract from dir name
            parts = _.split("-")
            if len(parts) > 1 and parts[1].isdigit():
                max_order = max(max_order, int(parts[1]))
    return max_order + 1


def _input_with_default(prompt, default=""):
    """Read input with a default value."""
    if default:
        val = input(f"{prompt} [{default}]: ").strip()
        return val if val else default
    return input(f"{prompt}: ").strip()


# --- Subcommands ---

def cmd_new(args):
    """Scaffold a new module."""
    name = args.name
    # Normalize name
    name = re.sub(r'[^a-z0-9-]', '-', name.lower()).strip('-')

    if args.from_yaml:
        # Non-interactive: load spec from YAML
        with open(args.from_yaml) as f:
            spec = yaml.safe_load(f) or {}
        title = spec.get("title", name.replace("-", " ").title())
        order = spec.get("order", _next_order())
        difficulty = spec.get("difficulty", "beginner")
        estimated_minutes = spec.get("estimated_minutes", 30)
        description = spec.get("description", "")
        prerequisites = spec.get("prerequisites", [])
        tags = spec.get("tags", [])
        mode = spec.get("mode", "simple")
    elif args.non_interactive:
        # Non-interactive with defaults
        order = _next_order()
        title = name.replace("-", " ").title()
        difficulty = "beginner"
        estimated_minutes = 30
        description = ""
        prerequisites = []
        tags = []
        mode = "simple"
    else:
        # Interactive wizard
        print(f"\n--- New Module Wizard ---\n")
        order = _next_order()
        order = int(_input_with_default("Order number", str(order)))
        title = _input_with_default("Title", name.replace("-", " ").title())
        difficulty = _input_with_default("Difficulty (beginner/intermediate/advanced)", "beginner")
        estimated_minutes = int(_input_with_default("Estimated minutes", "30"))
        description = _input_with_default("Description (one line)", "")
        prereq_str = _input_with_default("Prerequisites (comma-separated module dirs)", "")
        prerequisites = [p.strip() for p in prereq_str.split(",") if p.strip()] if prereq_str else []
        tags_str = _input_with_default("Tags (comma-separated)", "")
        tags = [t.strip() for t in tags_str.split(",") if t.strip()] if tags_str else []
        mode = _input_with_default("Validation mode (simple/staged)", "simple")

    dir_name = f"module-{order:02d}-{name}"
    mod_path = REPO_ROOT / dir_name

    if mod_path.exists():
        print(f"ERROR: {dir_name} already exists", file=sys.stderr)
        sys.exit(1)

    # Create directory structure
    mod_path.mkdir(parents=True)
    (mod_path / "challenges").mkdir()

    # module.yaml
    if mode == "staged":
        validation_block = (
            "stages:\n"
            "  - name: \"Prerequisites\"\n"
            "    on_fail: pending\n"
            "    checks:\n"
            "      - name: \"TODO: first check\"\n"
            "        type: script\n"
            "        run: \"true\"\n"
            "  - name: \"Main\"\n"
            "    on_fail: in_progress\n"
            "    checks:\n"
            "      - name: \"TODO: second check\"\n"
            "        type: script\n"
            "        run: \"true\""
        )
    else:
        validation_block = (
            "checks:\n"
            "  - name: \"TODO: first check\"\n"
            "    type: script\n"
            "    run: \"true\""
        )

    check_types_str = ", ".join(sorted(CHECK_TYPES.keys()))
    yaml_content = MODULE_YAML_TEMPLATE.format(
        title=title,
        order=order,
        difficulty=difficulty,
        estimated_minutes=estimated_minutes,
        description=description,
        prerequisites=yaml.dump(prerequisites, default_flow_style=True).strip() if prerequisites else "[]",
        tags=yaml.dump(tags, default_flow_style=True).strip() if tags else "[]",
        check_types=check_types_str,
        validation_block=validation_block,
    )
    (mod_path / "module.yaml").write_text(yaml_content)

    # README.md
    if prerequisites:
        prereq_list = "\n".join(f"- {p}" for p in prerequisites)
    else:
        prereq_list = "- None"
    readme_content = README_TEMPLATE.format(
        order=order,
        title=title,
        prerequisites_list=prereq_list,
        dir_name=dir_name,
    )
    (mod_path / "README.md").write_text(readme_content)

    # challenges/hints.md and solution.md
    (mod_path / "challenges" / "hints.md").write_text(
        HINTS_TEMPLATE.format(order=order, title=title)
    )
    (mod_path / "challenges" / "solution.md").write_text(
        SOLUTION_TEMPLATE.format(order=order, title=title)
    )

    # Generate validate.sh
    gen_module(dir_name, dry_run=False)

    # i18n stubs (optional)
    if not args.non_interactive and not args.from_yaml:
        create_i18n = _input_with_default("Create i18n stubs? (y/n)", "n")
        if create_i18n.lower() == "y":
            i18n_path = REPO_ROOT / "i18n" / "en" / dir_name
            i18n_path.mkdir(parents=True, exist_ok=True)
            (i18n_path / "README.md").write_text(readme_content)

    print(f"\nCreated {dir_name}/")
    print(f"  module.yaml")
    print(f"  README.md")
    print(f"  validate.sh")
    print(f"  challenges/hints.md")
    print(f"  challenges/solution.md")
    print(f"\nNext steps:")
    print(f"  1. Edit {dir_name}/module.yaml — define your validation checks")
    print(f"  2. Edit {dir_name}/README.md — write instructions")
    print(f"  3. Run: python3 tools/capi-author.py generate {dir_name}")
    print(f"  4. Run: python3 tools/capi-author.py validate {dir_name}")


def cmd_validate(args):
    """Validate module.yaml schema + content integrity."""
    if args.all:
        errors = validate_all_modules(REPO_ROOT)
        # Also check for structural issues
        modules = _discover_modules()
        for dir_name, meta in modules:
            mod_path = REPO_ROOT / dir_name
            if not (mod_path / "README.md").exists():
                errors.append(ValidationError(dir_name, "missing README.md"))
            if not (mod_path / "challenges").is_dir():
                errors.append(ValidationError(dir_name, "missing challenges/ directory"))

        if errors:
            print(f"Found {len(errors)} issue(s):\n")
            for e in errors:
                print(f"  ERROR: {e}")
            sys.exit(1)
        else:
            yaml_count = sum(1 for _, m in modules if m is not None)
            print(f"All {yaml_count} modules with module.yaml pass validation.")
    else:
        mod_dir = args.module
        yaml_path = REPO_ROOT / mod_dir / "module.yaml"
        if not yaml_path.exists():
            print(f"ERROR: {mod_dir}/module.yaml not found", file=sys.stderr)
            sys.exit(1)

        all_module_dirs = [d for d, _ in _discover_modules()]
        errors = validate_module(yaml_path, all_modules=all_module_dirs)

        mod_path = REPO_ROOT / mod_dir
        if not (mod_path / "README.md").exists():
            errors.append(ValidationError(mod_dir, "missing README.md"))
        if not (mod_path / "challenges").is_dir():
            errors.append(ValidationError(mod_dir, "missing challenges/ directory"))

        if errors:
            print(f"Found {len(errors)} issue(s):\n")
            for e in errors:
                print(f"  ERROR: {e}")
            sys.exit(1)
        else:
            print(f"{mod_dir}: OK")


def cmd_generate(args):
    """Generate validate.sh from module.yaml."""
    if args.all:
        ok = 0
        fail = 0
        for mod_dir in sorted(REPO_ROOT.glob("module-*")):
            if mod_dir.name.startswith("module-00"):
                continue
            if (mod_dir / "module.yaml").exists():
                if args.diff:
                    _generate_with_diff(mod_dir.name)
                    ok += 1
                else:
                    if gen_module(mod_dir.name, dry_run=False):
                        ok += 1
                    else:
                        fail += 1
        print(f"\nDone: {ok} generated, {fail} failed")
        if fail:
            sys.exit(1)
    else:
        mod_dir = args.module
        if args.diff:
            _generate_with_diff(mod_dir)
        else:
            if not gen_module(mod_dir, dry_run=False):
                sys.exit(1)


def _generate_with_diff(module_dir: str):
    """Generate and show diff against existing validate.sh."""
    import difflib
    mod_path = REPO_ROOT / module_dir
    existing_path = mod_path / "validate.sh"

    old_content = ""
    if existing_path.exists():
        old_content = existing_path.read_text()

    # Generate to string by doing a dry run capture
    yaml_path = mod_path / "module.yaml"
    with open(yaml_path) as f:
        meta = yaml.safe_load(f) or {}

    generate_simple = _gen_mod.generate_simple
    generate_staged = _gen_mod.generate_staged
    has_checks = "checks" in meta
    has_stages = "stages" in meta

    if not has_checks and not has_stages:
        print(f"SKIP: {module_dir} has no checks/stages")
        return

    new_content = generate_simple(meta, module_dir) if has_checks else generate_staged(meta, module_dir)

    if old_content == new_content:
        print(f"{module_dir}: no changes")
        return

    diff = difflib.unified_diff(
        old_content.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile=f"{module_dir}/validate.sh (current)",
        tofile=f"{module_dir}/validate.sh (generated)",
    )
    print("".join(diff))


def cmd_migrate(args):
    """Reverse-engineer module.yaml from existing validate.sh."""
    if args.all:
        for mod_dir in sorted(REPO_ROOT.glob("module-*")):
            if mod_dir.name.startswith("module-00"):
                continue
            _migrate_one(mod_dir.name, args.dry_run)
    else:
        _migrate_one(args.module, args.dry_run)


def _migrate_one(module_dir: str, dry_run: bool = False):
    """Migrate a single module's validate.sh to module.yaml."""
    mod_path = REPO_ROOT / module_dir
    validate_path = mod_path / "validate.sh"
    yaml_path = mod_path / "module.yaml"

    if yaml_path.exists():
        print(f"SKIP: {module_dir}/module.yaml already exists")
        return

    if not validate_path.exists():
        print(f"SKIP: {module_dir}/validate.sh not found")
        return

    content = validate_path.read_text()

    # Extract order from directory name
    parts = module_dir.split("-")
    order = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 99

    # Extract title from module dir name
    name_parts = parts[2:] if len(parts) > 2 else [module_dir]
    title = " ".join(p.capitalize() for p in name_parts)

    # Detect mode: staged (exit 100/101) vs simple (ERRORS accumulation)
    has_exit_100 = "exit 100" in content
    has_exit_101 = "exit 101" in content
    has_errors = "ERRORS=" in content or "ERRORS=$" in content
    is_staged = has_exit_100 or has_exit_101

    # Pattern-match check types
    checks = []

    # command -v checks → tool_exists
    for m in re.finditer(r'command -v (\w+)', content):
        tool = m.group(1)
        checks.append({
            "name": f"{tool} installed",
            "type": "tool_exists",
            "tool": tool,
        })

    # kubectl config get-contexts → context_exists
    for m in re.finditer(r'kubectl config get-contexts (\S+)', content):
        ctx = m.group(1)
        checks.append({
            "name": f"Context {ctx} exists",
            "type": "context_exists",
            "context": ctx,
        })

    # kubectl get cluster/clusterresourceset/etc NAME → resource_exists
    for m in re.finditer(r'kubectl get (\w+) ([\w-]+) &>', content):
        kind = m.group(1)
        name = m.group(2)
        if kind in ("pods", "nodes"):
            continue
        check_name = f"{kind} {name} exists"
        if not any(c["name"] == check_name for c in checks):
            checks.append({
                "name": check_name,
                "type": "resource_exists",
                "kind": kind,
                "resource_name": name,
            })

    # kubectl get pods -n NS ... grep Running → pods_running
    for m in re.finditer(r'kubectl get pods -n (\S+)(.*?)grep.*?Running', content, re.DOTALL):
        ns = m.group(1)
        selector_match = re.search(r'-l (\S+)', m.group(2))
        check_entry = {
            "name": f"Pods running in {ns}",
            "type": "pods_running",
            "namespace": ns,
        }
        if selector_match:
            check_entry["selector"] = selector_match.group(1)
        if not any(c["name"] == check_entry["name"] for c in checks):
            checks.append(check_entry)

    # kubectl get pods -A ... grep pattern → pods_running
    for m in re.finditer(r"kubectl get pods -A.*?grep -E '([^']+)'.*?grep.*?Running", content, re.DOTALL):
        pattern = m.group(1)
        check_entry = {
            "name": f"CAPI pods running ({pattern})",
            "type": "pods_running",
            "pattern": pattern,
            "grep_status": "Running",
        }
        if not any("CAPI pods" in c["name"] for c in checks):
            checks.append(check_entry)

    # clusterctl get kubeconfig CLUSTER → ensure_kubeconfig
    for m in re.finditer(r'clusterctl get kubeconfig (\S+)\s*>\s*(\S+)', content):
        cluster = m.group(1)
        output = m.group(2)
        check_name = f"Kubeconfig for {cluster}"
        if not any(c["name"] == check_name for c in checks):
            checks.append({
                "name": check_name,
                "type": "ensure_kubeconfig",
                "cluster_name": cluster,
                "output_file": output,
            })

    # kubectl --kubeconfig=FILE get nodes → nodes_ready
    for m in re.finditer(r'kubectl --kubeconfig=(\S+) get nodes', content):
        kc = m.group(1)
        check_name = f"Nodes ready ({kc})"
        if not any(c["name"] == check_name for c in checks):
            checks.append({
                "name": check_name,
                "type": "nodes_ready",
                "kubeconfig": kc,
                "min_count": 2,
            })

    # kubectl --kubeconfig=FILE get KIND NAME → remote_resource
    for m in re.finditer(r'kubectl --kubeconfig=(\S+) get (\w+) ([\w-]+)', content):
        kc = m.group(1)
        kind = m.group(2)
        name = m.group(3)
        if kind in ("pods", "nodes"):
            continue
        check_name = f"Remote {kind} {name}"
        if not any(c["name"] == check_name for c in checks):
            checks.append({
                "name": check_name,
                "type": "remote_resource",
                "kubeconfig": kc,
                "kind": kind,
                "resource_name": name,
            })

    # kubectl --kubeconfig=FILE get pods -n NS ... grep Running → remote_pods
    for m in re.finditer(r'kubectl --kubeconfig=(\S+) get pods(?:\s+-n\s+(\S+))?(?:\s+-l\s+(\S+))?.*?grep.*?Running', content, re.DOTALL):
        kc = m.group(1)
        ns = m.group(2) or ""
        sel = m.group(3) or ""
        check_entry = {
            "name": f"Remote pods running ({kc})",
            "type": "remote_pods",
            "kubeconfig": kc,
        }
        if ns:
            check_entry["namespace"] = ns
        if sel:
            check_entry["selector"] = sel
        if not any(c["name"] == check_entry["name"] for c in checks):
            checks.append(check_entry)

    # kubectl get clusters ... grep pattern | wc -l → resource_count
    for m in re.finditer(r'kubectl get (\w+)s? --no-headers.*?grep -E ["\']([^"\']+)', content):
        kind = m.group(1)
        pattern = m.group(2)
        min_match = re.search(r'-eq (\d+)', content[m.end():m.end()+200])
        min_count = int(min_match.group(1)) if min_match else 1
        check_name = f"{kind}s matching {pattern}"
        if not any(c["name"] == check_name for c in checks):
            checks.append({
                "name": check_name,
                "type": "resource_count",
                "kind": kind,
                "pattern": pattern,
                "min_count": min_count,
            })

    # kubectl get ... -o jsonpath → field_equals
    for m in re.finditer(r"kubectl get (\w+) (\S+) -o jsonpath='([^']+)'", content):
        kind = m.group(1)
        name = m.group(2)
        jp = m.group(3)
        # Try to find expected value
        exp_match = re.search(r'==\s*"([^"]+)"', content[m.end():m.end()+200])
        expected = exp_match.group(1) if exp_match else "TODO"
        check_name = f"{kind} {name} field check"
        if not any(c["name"] == check_name for c in checks):
            checks.append({
                "name": check_name,
                "type": "field_equals",
                "kind": kind,
                "resource_name": name,
                "jsonpath": jp,
                "expected": expected,
            })

    # Helm checks → helm_release
    for m in re.finditer(r'helm status (\S+)\s+-n\s+(\S+)', content):
        release = m.group(1)
        ns = m.group(2)
        checks.append({
            "name": f"Helm release {release}",
            "type": "helm_release",
            "release": release,
            "namespace": ns,
        })

    # HelmChartProxy checks via jq → script type
    for m in re.finditer(r'kubectl get helmchartprox.*?jq.*?select', content, re.DOTALL):
        # Complex jq — keep as script
        block = content[m.start():m.end()+300]
        end_fi = block.find("\nfi")
        if end_fi > 0:
            block = block[:end_fi+3]
        # Just note it — we'll use script type for complex checks
        pass

    # Remove duplicate checks
    seen_names = set()
    unique_checks = []
    for c in checks:
        if c["name"] not in seen_names:
            seen_names.add(c["name"])
            unique_checks.append(c)
    checks = unique_checks

    # Build YAML structure
    meta = {
        "title": title,
        "order": order,
        "difficulty": "beginner",  # TODO: fill in
        "estimated_minutes": 30,   # TODO: fill in
        "description": f"TODO: Add description for {title}",
        "prerequisites": [],       # TODO: fill in
        "tags": [],                # TODO: fill in
    }

    if is_staged and checks:
        # Split checks into stages based on detection
        prereq_checks = [c for c in checks if c["type"] in ("tool_exists", "context_exists")]
        main_checks = [c for c in checks if c not in prereq_checks]

        stages = []
        if prereq_checks:
            stages.append({
                "name": "Prerequisites",
                "on_fail": "pending",
                "checks": prereq_checks,
            })
        if main_checks:
            stages.append({
                "name": "Main",
                "on_fail": "in_progress",
                "checks": main_checks,
            })
        if not stages:
            stages.append({
                "name": "Main",
                "on_fail": "in_progress",
                "checks": [{"name": "TODO: add checks", "type": "script", "run": "true"}],
            })
        meta["stages"] = stages
    elif checks:
        meta["checks"] = checks
    else:
        # No checks detected — add placeholder
        meta["checks"] = [{"name": "TODO: add checks", "type": "script", "run": "true"}]

    yaml_str = yaml.dump(meta, default_flow_style=False, sort_keys=False, allow_unicode=True)

    if dry_run:
        print(f"--- {module_dir}/module.yaml (draft) ---")
        print(yaml_str)
        return

    with open(yaml_path, "w") as f:
        f.write(yaml_str)
    print(f"OK: {module_dir}/module.yaml generated (draft — review TODO items)")


def cmd_list(args):
    """List all modules with metadata."""
    modules = _discover_modules()

    # Header
    print(f"{'ORDER':<7} {'MODULE':<35} {'TITLE':<30} {'DIFFICULTY':<14} {'TIME'}")
    print("-" * 100)

    for dir_name, meta in modules:
        if meta:
            order = meta.get("order", "??")
            title = meta.get("title", dir_name)[:28]
            difficulty = meta.get("difficulty", "-")
            est = meta.get("estimated_minutes")
            time_str = f"{est}m" if est else "-"
        else:
            parts = dir_name.split("-")
            order = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else "??"
            title = dir_name
            difficulty = "-"
            time_str = "-"
        order_str = f"{order:02d}" if isinstance(order, int) else str(order)
        yaml_marker = "" if meta else " (no yaml)"
        print(f"{order_str:<7} {dir_name:<35} {title:<30} {difficulty:<14} {time_str}{yaml_marker}")


def cmd_check_types(args):
    """List all available validation check types."""
    print(f"\n{'TYPE':<22} {'REQUIRED FIELDS':<45} {'DESCRIPTION'}")
    print("-" * 95)

    descriptions = {
        "tool_exists": "Check if a CLI tool is installed",
        "context_exists": "Check if a kubectl context exists",
        "resource_exists": "Check if a Kubernetes resource exists",
        "field_equals": "Check a resource field value via jsonpath",
        "pods_running": "Check pods are running (by ns/selector/pattern)",
        "resource_count": "Check minimum count of resources",
        "nodes_ready": "Check cluster nodes are Ready",
        "ensure_kubeconfig": "Fetch and cache kubeconfig for a cluster",
        "remote_resource": "Check resource on a remote cluster",
        "remote_pods": "Check pods running on a remote cluster",
        "script": "Run arbitrary bash script",
        "helm_release": "Check a Helm release is deployed",
        "namespace_exists": "Check if a namespace exists",
        "crds_exist": "Check if CRDs are installed",
        "file_exists": "Check if a file exists on disk",
        "http_reachable": "Check if a URL is reachable via HTTP",
    }

    for ctype, spec in sorted(CHECK_TYPES.items()):
        required = ", ".join(spec["required"]) if spec["required"] else "(none)"
        desc = descriptions.get(ctype, "")
        print(f"{ctype:<22} {required:<45} {desc}")

    print(f"\nTotal: {len(CHECK_TYPES)} check types available")
    print(f"\nCustom checks can be defined inline in module.yaml via 'custom_checks'.")


# --- Main ---

def main():
    parser = argparse.ArgumentParser(
        description="CAPI Workshop Module Authoring CLI",
        prog="capi-author",
    )
    sub = parser.add_subparsers(dest="command", help="Available commands")

    # new
    p_new = sub.add_parser("new", help="Scaffold a new module")
    p_new.add_argument("name", help="Module name (e.g., network-policies)")
    p_new.add_argument("--non-interactive", action="store_true", help="Use defaults without prompting")
    p_new.add_argument("--from-yaml", help="Path to a spec YAML for non-interactive creation")

    # validate
    p_val = sub.add_parser("validate", help="Validate module.yaml schema + integrity")
    p_val.add_argument("module", nargs="?", help="Module directory name")
    p_val.add_argument("--all", action="store_true", help="Validate all modules")

    # generate
    p_gen = sub.add_parser("generate", help="Generate validate.sh from module.yaml")
    p_gen.add_argument("module", nargs="?", help="Module directory name")
    p_gen.add_argument("--all", action="store_true", help="Generate for all modules")
    p_gen.add_argument("--diff", action="store_true", help="Show diff before writing")
    p_gen.add_argument("--force", action="store_true", help="Overwrite existing validate.sh")

    # migrate
    p_mig = sub.add_parser("migrate", help="Reverse-engineer module.yaml from validate.sh")
    p_mig.add_argument("module", nargs="?", help="Module directory name")
    p_mig.add_argument("--all", action="store_true", help="Migrate all modules")
    p_mig.add_argument("--dry-run", action="store_true", help="Preview without writing")

    # list
    sub.add_parser("list", help="List all modules with metadata")

    # check-types
    sub.add_parser("check-types", help="List all available check types")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "new": cmd_new,
        "validate": cmd_validate,
        "generate": cmd_generate,
        "migrate": cmd_migrate,
        "list": cmd_list,
        "check-types": cmd_check_types,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
