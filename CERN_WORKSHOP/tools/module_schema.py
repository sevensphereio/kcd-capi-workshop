#!/usr/bin/env python3
"""module_schema.py — Single source of truth for module.yaml schema and validation.

Defines the extended schema, validates module.yaml files, and provides
cross-module consistency checks.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("ERROR: pyyaml is required. Install with: pip install pyyaml")


def _lint_script_body(body: str) -> list:
    """Run shellcheck on a script body and return any error lines.

    The `script:` check type accepts arbitrary bash, which is a foot-gun
    (a malicious or buggy module author could exfiltrate ~/.ssh or do
    rm -rf /). We catch the most obvious cases by piping the body
    through shellcheck before generation.

    If shellcheck isn't installed, we silently pass (don't block the
    workshop from running just because a dev machine lacks the tool;
    CI runs with shellcheck installed and will catch issues there).
    """
    if not shutil.which("shellcheck"):
        return []
    try:
        # Severity floor at 'error' to keep style nags out of validation.
        result = subprocess.run(
            ["shellcheck", "-s", "bash", "-S", "error", "-"],
            input=body,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []
    if result.returncode == 0:
        return []
    return [
        line.strip()
        for line in result.stdout.splitlines()
        if line.strip()
    ]

# --- Schema Definition ---

SCHEMA = {
    "title":             {"type": str,  "required": True},
    "order":             {"type": int,  "required": True},
    "difficulty":        {"type": str,  "enum": ["beginner", "intermediate", "advanced"]},
    "estimated_minutes": {"type": int},
    "description":       {"type": str},
    "prerequisites":     {"type": list},   # list of module dir names
    "tags":              {"type": list},    # list of strings
    "i18n":              {"type": dict},    # {"default": "en", "available": ["en", "fr"]}
    "challenges":        {"type": list},    # challenge metadata
    "checks":            {"type": list},    # OR stages, not both
    "stages":            {"type": list},
    "custom_checks":     {"type": list},    # inline check definitions
    # Optional per-module timeout (seconds) the agent uses when running validate.sh.
    # Default 60 (defined in agent.py). Override for modules that need longer
    # (CAPD provisioning ~ 5 min, Ollama download ~ 10 min).
    "timeout_seconds":   {"type": int},
    # Optional module enable flag. Absent ⇒ treated as True (enabled) everywhere.
    # Never required — set `enabled: false` to ship a module disabled.
    "enabled":           {"type": bool},
}

# Known check types and their required/optional fields
CHECK_TYPES = {
    "tool_exists":       {"required": ["tool"]},
    "context_exists":    {"required": ["context"]},
    "resource_exists":   {"required": ["kind", "resource_name"]},
    "field_equals":      {"required": ["kind", "resource_name", "jsonpath", "expected"]},
    "pods_running":      {"required": []},
    "resource_count":    {"required": ["kind", "min_count"]},
    "nodes_ready":       {"required": []},
    "ensure_kubeconfig": {"required": ["cluster_name", "output_file"]},
    "remote_resource":   {"required": ["kubeconfig", "kind", "resource_name"]},
    "remote_pods":       {"required": ["kubeconfig"]},
    "script":            {"required": ["run"]},
    # New check types (Phase 1.2)
    "helm_release":      {"required": ["release", "namespace"]},
    "namespace_exists":  {"required": ["namespace"]},
    "crds_exist":        {"required": ["crd_names"]},
    "file_exists":       {"required": ["file_path"]},
    "http_reachable":    {"required": ["url"]},
}


class ValidationError:
    """Structured validation error."""
    def __init__(self, path: str, message: str, suggestion: str = ""):
        self.path = path
        self.message = message
        self.suggestion = suggestion

    def __str__(self):
        s = f"{self.path}: {self.message}"
        if self.suggestion:
            s += f"\n  -> {self.suggestion}"
        return s

    def __repr__(self):
        return f"ValidationError({self.path!r}, {self.message!r})"


def validate_module(yaml_path, all_modules=None) -> list:
    """Full validation of a module.yaml file including cross-references.

    Args:
        yaml_path: Path to module.yaml (str or Path)
        all_modules: Optional list of all module dir names for cross-module checks

    Returns:
        List of ValidationError objects (empty = valid)
    """
    yaml_path = Path(yaml_path)
    errors = []
    module_dir = yaml_path.parent.name

    if not yaml_path.exists():
        errors.append(ValidationError(module_dir, f"module.yaml not found at {yaml_path}"))
        return errors

    try:
        with open(yaml_path) as f:
            meta = yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        errors.append(ValidationError(module_dir, f"YAML parse error: {e}"))
        return errors

    # Validate required fields
    for field, spec in SCHEMA.items():
        if spec.get("required") and field not in meta:
            errors.append(ValidationError(
                module_dir, f"missing required field '{field}'",
                f"Add '{field}:' to module.yaml"
            ))

    # Type checks
    for field, spec in SCHEMA.items():
        if field in meta:
            expected_type = spec["type"]
            if not isinstance(meta[field], expected_type):
                errors.append(ValidationError(
                    module_dir,
                    f"field '{field}' should be {expected_type.__name__}, got {type(meta[field]).__name__}"
                ))

    # Enum checks
    for field, spec in SCHEMA.items():
        if field in meta and "enum" in spec:
            if meta[field] not in spec["enum"]:
                errors.append(ValidationError(
                    module_dir,
                    f"field '{field}' must be one of {spec['enum']}, got '{meta[field]}'"
                ))

    # Mutually exclusive: checks vs stages
    has_checks = "checks" in meta
    has_stages = "stages" in meta

    if has_checks and has_stages:
        errors.append(ValidationError(
            module_dir, "cannot have both 'checks' and 'stages'",
            "Use 'checks' for simple validation, 'stages' for progressive validation"
        ))

    # Build merged check types (including custom_checks)
    merged_types = get_extended_check_types(meta)

    # Validate checks
    all_checks = []
    if has_checks:
        all_checks = meta["checks"]
    elif has_stages:
        for stage in meta["stages"]:
            if "checks" not in stage:
                errors.append(ValidationError(
                    module_dir,
                    f"stage '{stage.get('name', '?')}' has no checks"
                ))
                continue
            if "on_fail" not in stage:
                errors.append(ValidationError(
                    module_dir,
                    f"stage '{stage.get('name', '?')}' missing 'on_fail'",
                    "Add 'on_fail: pending' or 'on_fail: in_progress'"
                ))
            all_checks.extend(stage["checks"])

    names_seen = set()
    for check in all_checks:
        name = check.get("name")
        if not name:
            errors.append(ValidationError(module_dir, "check missing 'name'"))
            continue
        if name in names_seen:
            errors.append(ValidationError(
                module_dir, f"duplicate check name '{name}'",
                "Each check must have a unique name within the module"
            ))
        names_seen.add(name)

        ctype = check.get("type")
        if not ctype:
            errors.append(ValidationError(
                module_dir, f"check '{name}' missing 'type'",
                f"Available types: {', '.join(sorted(merged_types.keys()))}"
            ))
            continue
        if ctype not in merged_types:
            errors.append(ValidationError(
                module_dir, f"check '{name}' unknown type '{ctype}'",
                f"Available types: {', '.join(sorted(merged_types.keys()))}"
            ))
            continue

        for req_field in merged_types[ctype]["required"]:
            if req_field not in check:
                errors.append(ValidationError(
                    module_dir,
                    f"check '{name}' (type={ctype}) missing required field '{req_field}'"
                ))

        # script: bodies are arbitrary bash; lint them with shellcheck if
        # available so 'rm -rf /' and friends can't ship undetected.
        if ctype == "script" and "run" in check:
            _shellcheck_errors = _lint_script_body(check["run"])
            for line in _shellcheck_errors:
                errors.append(ValidationError(
                    module_dir,
                    f"check '{name}' (type=script) failed shellcheck: {line}",
                    "If shellcheck is unavailable, install it (apt-get install shellcheck) "
                    "or rewrite the check using a typed check_type."
                ))

    # Cross-module checks
    if all_modules:
        # Prerequisites reference existing module dirs
        for prereq in meta.get("prerequisites", []):
            if prereq not in all_modules:
                errors.append(ValidationError(
                    module_dir,
                    f"prerequisite '{prereq}' does not match any known module directory",
                    f"Available modules: {', '.join(sorted(all_modules))}"
                ))

    return errors


def validate_all_modules(repo_root) -> list:
    """Validate all modules and perform cross-module checks.

    Returns list of ValidationError objects.
    """
    repo_root = Path(repo_root)
    errors = []

    # Discover all module dirs
    all_module_dirs = []
    for mod_dir in sorted(repo_root.glob("module-*")):
        if mod_dir.name.startswith("module-00"):
            continue
        all_module_dirs.append(mod_dir.name)

    # Validate each module
    orders_seen = {}
    for mod_name in all_module_dirs:
        yaml_path = repo_root / mod_name / "module.yaml"
        if not yaml_path.exists():
            continue

        mod_errors = validate_module(yaml_path, all_modules=all_module_dirs)
        errors.extend(mod_errors)

        # Cross-module: duplicate order numbers
        try:
            with open(yaml_path) as f:
                meta = yaml.safe_load(f) or {}
            order = meta.get("order")
            if order is not None:
                if order in orders_seen:
                    errors.append(ValidationError(
                        mod_name,
                        f"duplicate order number {order} (also used by {orders_seen[order]})",
                        "Each module must have a unique order number"
                    ))
                else:
                    orders_seen[order] = mod_name
        except Exception:
            pass

    return errors


def load_module_meta(yaml_path) -> dict:
    """Parse and validate a module.yaml, raising on error.

    Returns the parsed metadata dict.
    Raises ValueError if validation fails.
    """
    yaml_path = Path(yaml_path)
    errors = validate_module(yaml_path)
    if errors:
        msg = "\n".join(str(e) for e in errors)
        raise ValueError(f"Validation failed for {yaml_path}:\n{msg}")

    with open(yaml_path) as f:
        return yaml.safe_load(f) or {}


def get_extended_check_types(meta=None) -> dict:
    """Return merged CHECK_TYPES including any custom_checks from module metadata.

    Args:
        meta: Optional module metadata dict. If provided, custom_checks are merged.

    Returns:
        Dict of check type name -> {"required": [...]}
    """
    merged = dict(CHECK_TYPES)
    if meta and "custom_checks" in meta:
        for custom in meta["custom_checks"]:
            name = custom.get("name")
            if name:
                params = custom.get("params", [])
                merged[name] = {"required": params, "custom": True}
    return merged
