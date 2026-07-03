#!/usr/bin/env python3
"""generate-validation.py — Generate validate.sh from module.yaml definitions.

Usage:
    python3 tools/generate-validation.py module-07-observability
    python3 tools/generate-validation.py --all
    python3 tools/generate-validation.py module-07-observability --dry-run
"""
import argparse
import os
import stat
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("ERROR: pyyaml is required. Install with: pip install pyyaml")

# Import schema and validation from module_schema
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_schema import CHECK_TYPES, get_extended_check_types, validate_module

REPO_ROOT = Path(__file__).resolve().parent.parent


def validate_module_yaml(meta: dict, module_dir: str) -> list[str]:
    """Validate module.yaml structure. Returns list of error messages.

    Delegates to module_schema.validate_module for schema checks,
    but also accepts a pre-loaded meta dict for backward compat.
    """
    yaml_path = REPO_ROOT / module_dir / "module.yaml"
    if yaml_path.exists():
        errors = validate_module(yaml_path)
        return [str(e) for e in errors]

    # Fallback: inline validation for pre-loaded meta
    errors = []
    if "title" not in meta:
        errors.append(f"{module_dir}: missing required field 'title'")
    if "order" not in meta:
        errors.append(f"{module_dir}: missing required field 'order'")

    has_checks = "checks" in meta
    has_stages = "stages" in meta

    if has_checks and has_stages:
        errors.append(f"{module_dir}: cannot have both 'checks' and 'stages'")
    if not has_checks and not has_stages:
        return errors

    merged_types = get_extended_check_types(meta)
    all_checks = []
    if has_checks:
        all_checks = meta["checks"]
    elif has_stages:
        for stage in meta["stages"]:
            if "checks" not in stage:
                errors.append(f"{module_dir}: stage '{stage.get('name', '?')}' has no checks")
                continue
            if "on_fail" not in stage:
                errors.append(f"{module_dir}: stage '{stage.get('name', '?')}' missing 'on_fail'")
            all_checks.extend(stage["checks"])

    names_seen = set()
    for check in all_checks:
        name = check.get("name")
        if not name:
            errors.append(f"{module_dir}: check missing 'name'")
            continue
        if name in names_seen:
            errors.append(f"{module_dir}: duplicate check name '{name}'")
        names_seen.add(name)

        ctype = check.get("type")
        if not ctype:
            errors.append(f"{module_dir}: check '{name}' missing 'type'")
            continue
        if ctype not in merged_types:
            errors.append(f"{module_dir}: check '{name}' unknown type '{ctype}'")
            continue

        for req_field in merged_types[ctype]["required"]:
            if req_field not in check:
                errors.append(f"{module_dir}: check '{name}' (type={ctype}) missing field '{req_field}'")

    return errors


def _shell_escape(s: str) -> str:
    """Escape a string for safe use in shell double quotes."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")


def _emit_check(check: dict, meta: dict = None) -> list[str]:
    """Emit bash lines for a single check. Returns list of lines."""
    lines = []
    ctype = check["type"]
    name = check.get("name", "")
    label = _shell_escape(name)

    if ctype == "tool_exists":
        tool = check["tool"]
        lines.append(f'require_tool {tool} --label "{label}"')

    elif ctype == "context_exists":
        ctx = check["context"]
        lines.append(f'require_context {ctx} --label "{label}"')

    elif ctype == "resource_exists":
        kind = check["kind"]
        rn = check["resource_name"]
        if isinstance(rn, list):
            names = " ".join(rn)
        else:
            names = rn
        lines.append(f'require_resource {kind} {names} --label "{label}"')

    elif ctype == "field_equals":
        kind = check["kind"]
        rn = check["resource_name"]
        jp = check["jsonpath"]
        exp = check["expected"]
        cmd = f'require_field_equals --kind {kind} --name {rn} --jsonpath \'{jp}\' --expected "{exp}"'
        if check.get("in_progress_values"):
            ipv = check["in_progress_values"]
            if isinstance(ipv, list):
                ipv = "|".join(str(v) for v in ipv)
            cmd += f' --in-progress-values "{ipv}"'
        cmd += f' --label "{label}"'
        lines.append(cmd)

    elif ctype == "pods_running":
        args = []
        if check.get("namespace"):
            args.append(f'--namespace {check["namespace"]}')
        if check.get("selector"):
            args.append(f'--selector "{check["selector"]}"')
        if check.get("pattern"):
            args.append(f'--pattern "{check["pattern"]}"')
        if check.get("grep_status"):
            args.append(f'--grep-status {check["grep_status"]}')
        if check.get("min_count"):
            args.append(f'--min-count {check["min_count"]}')
        args.append(f'--label "{label}"')
        lines.append("require_pods_running " + " ".join(args))

    elif ctype == "resource_count":
        kind = check["kind"]
        args = [f"--kind {kind}"]
        if check.get("pattern"):
            args.append(f'--pattern "{check["pattern"]}"')
        args.append(f'--min-count {check["min_count"]}')
        args.append(f'--label "{label}"')
        lines.append("require_resource_count " + " ".join(args))

    elif ctype == "nodes_ready":
        args = []
        if check.get("kubeconfig"):
            args.append(f'--kubeconfig {check["kubeconfig"]}')
        if check.get("min_count"):
            args.append(f'--min-count {check["min_count"]}')
        args.append(f'--label "{label}"')
        lines.append("require_nodes_ready " + " ".join(args))

    elif ctype == "ensure_kubeconfig":
        cluster = check["cluster_name"]
        output = check["output_file"]
        lines.append(f'ensure_kubeconfig --cluster {cluster} --output {output} --label "{label}"')

    elif ctype == "remote_resource":
        kc = check["kubeconfig"]
        kind = check["kind"]
        rn = check["resource_name"]
        lines.append(f'require_remote_resource --kubeconfig {kc} {kind} {rn} --label "{label}"')

    elif ctype == "remote_pods":
        kc = check["kubeconfig"]
        args = [f"--kubeconfig {kc}"]
        if check.get("namespace"):
            args.append(f'--namespace {check["namespace"]}')
        if check.get("selector"):
            args.append(f'--selector "{check["selector"]}"')
        if check.get("pattern"):
            args.append(f'--pattern "{check["pattern"]}"')
        if check.get("grep_status"):
            args.append(f'--grep-status {check["grep_status"]}')
        if check.get("min_count"):
            args.append(f'--min-count {check["min_count"]}')
        args.append(f'--label "{label}"')
        lines.append("require_remote_pods " + " ".join(args))

    elif ctype == "script":
        script_body = check["run"].strip()
        lines.append(f'# Script check: {name}')
        lines.append(f'if ! ( {script_body} ) &>/dev/null; then')
        lines.append(f'    check_ko "{label}"')
        lines.append("else")
        lines.append(f'    check_ok "{label}"')
        lines.append("fi")

    # --- New check types ---

    elif ctype == "helm_release":
        release = check["release"]
        ns = check["namespace"]
        args = [f"--release {release}", f"--namespace {ns}"]
        if check.get("status"):
            args.append(f'--status {check["status"]}')
        args.append(f'--label "{label}"')
        lines.append("require_helm_release " + " ".join(args))

    elif ctype == "namespace_exists":
        ns = check["namespace"]
        lines.append(f'require_namespace {ns} --label "{label}"')

    elif ctype == "crds_exist":
        crd_names = check["crd_names"]
        if isinstance(crd_names, list):
            names = " ".join(crd_names)
        else:
            names = crd_names
        lines.append(f'require_crds {names} --label "{label}"')

    elif ctype == "file_exists":
        fp = check["file_path"]
        lines.append(f'require_file_exists {fp} --label "{label}"')

    elif ctype == "http_reachable":
        url = check["url"]
        args = [f'--url "{url}"']
        if check.get("timeout"):
            args.append(f'--timeout {check["timeout"]}')
        args.append(f'--label "{label}"')
        lines.append("require_http_reachable " + " ".join(args))

    else:
        # Custom check type — look up in custom_checks
        if meta and "custom_checks" in meta:
            for custom in meta["custom_checks"]:
                if custom.get("name") == ctype:
                    script_body = custom.get("script", "").strip()
                    # Substitute parameters
                    for param in custom.get("params", []):
                        val = check.get(param, "")
                        script_body = script_body.replace(f"${{{param}}}", str(val))
                    script_body = script_body.replace("$LABEL", label)
                    lines.append(f'# Custom check: {name}')
                    lines.extend(script_body.split("\n"))
                    break

    return lines


def generate_simple(meta: dict, module_dir: str) -> str:
    """Generate validate.sh for simple checks mode (error accumulation)."""
    lines = _header(meta, module_dir)

    for check in meta["checks"]:
        lines.append("")
        lines.extend(_emit_check(check, meta))

    lines.append("")
    title = meta.get("title", module_dir.upper())
    order = meta.get("order", "")
    lines.append(f'finish "MODULE {order:02d} VALIDATED!"' if isinstance(order, int) else f'finish "{title} VALIDATED!"')
    return "\n".join(lines) + "\n"


def generate_staged(meta: dict, module_dir: str) -> str:
    """Generate validate.sh for staged mode (progressive exit codes)."""
    lines = _header(meta, module_dir)

    for stage in meta["stages"]:
        stage_name = stage.get("name", "stage")
        on_fail = stage.get("on_fail", "in_progress")
        lines.append("")
        lines.append(f"# --- Stage: {stage_name} ---")

        for check in stage.get("checks", []):
            lines.extend(_emit_check(check, meta))

        # After each stage's checks, if any failed, exit with appropriate code
        if on_fail == "pending":
            lines.append(f'if [ "$ERRORS" -gt 0 ]; then exit_pending "{stage_name}: not ready"; fi')
        else:
            lines.append(f'if [ "$ERRORS" -gt 0 ]; then exit_in_progress "{stage_name}: in progress"; fi')

    lines.append("")
    order = meta.get("order", "")
    lines.append(f'finish "MODULE {order:02d} VALIDATED!"' if isinstance(order, int) else 'finish "VALIDATED!"')
    return "\n".join(lines) + "\n"


def _header(meta: dict, module_dir: str) -> list[str]:
    """Generate the common script header."""
    title = meta.get("title", module_dir)
    order = meta.get("order", "")
    order_str = f"{order:02d}" if isinstance(order, int) else str(order)
    return [
        "#!/bin/bash",
        f"# AUTO-GENERATED from module.yaml by tools/generate-validation.py",
        f"# To regenerate: python3 tools/generate-validation.py {module_dir}",
        f'source "$(dirname "$0")/../tools/validate-lib.sh"',
        f'mod_header "Module {order_str} — {title}"',
    ]


def generate_module(module_dir: str, dry_run: bool = False) -> bool:
    """Generate validate.sh for a single module. Returns True on success."""
    mod_path = REPO_ROOT / module_dir
    yaml_path = mod_path / "module.yaml"

    if not yaml_path.exists():
        print(f"SKIP: {module_dir}/module.yaml not found", file=sys.stderr)
        return False

    with open(yaml_path) as f:
        meta = yaml.safe_load(f) or {}

    errors = validate_module_yaml(meta, module_dir)
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return False

    # Enable/disable: module.yaml `enabled:` is the source of truth. When a module
    # is disabled, write a `.disabled` marker (the single fact bash consumers read)
    # and skip generating validate.sh so discovery loops omit it. When enabled
    # (True or absent), remove any stale marker before (re)generating validate.sh.
    marker_path = mod_path / ".disabled"
    if meta.get("enabled", True) is False:
        if not dry_run:
            marker_path.write_text(
                "# generated: module disabled via module.yaml enabled:false\n"
            )
            print(f"OK: {module_dir}/.disabled written (module disabled)")
        else:
            print(f"--- {module_dir}: disabled (would write .disabled, skip validate.sh) ---")
        return True
    if not dry_run and marker_path.exists():
        try:
            os.remove(marker_path)
            print(f"OK: {module_dir}/.disabled removed (module enabled)")
        except OSError:
            pass

    has_checks = "checks" in meta
    has_stages = "stages" in meta

    if not has_checks and not has_stages:
        print(f"SKIP: {module_dir}/module.yaml has no checks or stages")
        return True

    if has_checks:
        script = generate_simple(meta, module_dir)
    else:
        script = generate_staged(meta, module_dir)

    if dry_run:
        print(f"--- {module_dir}/validate.sh ---")
        print(script)
        return True

    out_path = mod_path / "validate.sh"
    with open(out_path, "w") as f:
        f.write(script)
    # Make executable
    out_path.chmod(out_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"OK: {module_dir}/validate.sh generated ({len(script.splitlines())} lines)")
    return True


def main():
    parser = argparse.ArgumentParser(description="Generate validate.sh from module.yaml")
    parser.add_argument("module", nargs="?", help="Module directory name (e.g., module-07-observability)")
    parser.add_argument("--all", action="store_true", help="Regenerate all modules")
    parser.add_argument("--dry-run", action="store_true", help="Print to stdout instead of writing")
    args = parser.parse_args()

    if not args.module and not args.all:
        parser.error("Specify a module name or --all")

    if args.all:
        ok_count = 0
        fail_count = 0
        for mod_dir in sorted(REPO_ROOT.glob("module-*")):
            if mod_dir.name.startswith("module-00"):
                continue
            if (mod_dir / "module.yaml").exists():
                if generate_module(mod_dir.name, dry_run=args.dry_run):
                    ok_count += 1
                else:
                    fail_count += 1
        print(f"\nDone: {ok_count} generated, {fail_count} failed")
        sys.exit(1 if fail_count > 0 else 0)
    else:
        if not generate_module(args.module, dry_run=args.dry_run):
            sys.exit(1)


if __name__ == "__main__":
    main()
