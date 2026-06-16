#!/usr/bin/env python3
"""
Layer import validator for the DDD backend.

Usage:
  # Check one file (called by the Claude Code PostToolUse hook)
  python3 scripts/check_layer_imports.py path/to/file.py

  # Check all Python files in the backend
  python3 scripts/check_layer_imports.py --all

Exit codes:
  0  no violations
  1  violations found
  2  usage error
"""
from __future__ import annotations

import ast
import sys
from dataclasses import dataclass, field
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# Rules: for each layer prefix, which imports are forbidden
# ---------------------------------------------------------------------------
FORBIDDEN: dict[str, list[str]] = {
    "domain": [
        "django",
        "rest_framework",
        "application",
        "infrastructure",
        "interfaces",
        # common third-party I/O libs
        "redis",
        "psycopg",
        "celery",
        "boto3",
        "requests",
        "httpx",
    ],
    "application": [
        "django",
        "rest_framework",
        "infrastructure",
        "interfaces",
        "redis",
        "psycopg",
        "celery",
        "boto3",
        "requests",
        "httpx",
    ],
    "infrastructure": [
        "interfaces",
    ],
}

# Cross-context interface imports
# interfaces/api/<ctx_a> must not import from interfaces/api/<ctx_b>
# This is checked separately below.


@dataclass
class Violation:
    file: Path
    line: int
    layer: str
    imported: str
    reason: str


def layer_of(path: Path) -> str | None:
    """Return the DDD layer name for a given file path, or None if not in a layer."""
    try:
        rel = path.relative_to(BACKEND_ROOT)
    except ValueError:
        return None
    parts = rel.parts
    if not parts:
        return None
    return parts[0]  # domain | application | infrastructure | interfaces | config


def context_of(path: Path) -> str | None:
    """Return the bounded context directory name for interfaces/api/<context>/ files."""
    try:
        rel = path.relative_to(BACKEND_ROOT / "interfaces" / "api")
    except ValueError:
        return None
    return rel.parts[0] if rel.parts else None


def extract_imports(source: str) -> list[tuple[int, str]]:
    """Return list of (lineno, top_level_module) from import statements."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    result: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                result.append((node.lineno, alias.name.split(".")[0]))
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                result.append((node.lineno, node.module.split(".")[0]))
    return result


def check_file(path: Path) -> list[Violation]:
    violations: list[Violation] = []
    layer = layer_of(path)
    if layer not in FORBIDDEN:
        return violations  # config, scripts, etc. — not checked

    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return violations

    imports = extract_imports(source)
    forbidden_for_layer = FORBIDDEN[layer]

    for lineno, top_module in imports:
        if top_module in forbidden_for_layer:
            violations.append(
                Violation(
                    file=path,
                    line=lineno,
                    layer=layer,
                    imported=top_module,
                    reason=f"{layer}/ must not import from '{top_module}'",
                )
            )

    # Cross-context interface check
    if layer == "interfaces":
        own_context = context_of(path)
        if own_context:
            for lineno, top_module in imports:
                if top_module == "interfaces":
                    # Deeper check: parse the full import to find the context
                    pass
            # Re-parse for full module paths
            try:
                tree = ast.parse(source)
            except SyntaxError:
                return violations

            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.module:
                    parts = node.module.split(".")
                    # interfaces.api.<context> imports
                    if (
                        len(parts) >= 3
                        and parts[0] == "interfaces"
                        and parts[1] == "api"
                        and parts[2] != own_context
                    ):
                        violations.append(
                            Violation(
                                file=path,
                                line=node.lineno,
                                layer=layer,
                                imported=node.module,
                                reason=(
                                    f"interfaces/api/{own_context}/ must not import "
                                    f"from interfaces/api/{parts[2]}/. "
                                    "Route through the application layer instead."
                                ),
                            )
                        )

    return violations


def collect_python_files() -> list[Path]:
    return [
        p
        for p in BACKEND_ROOT.rglob("*.py")
        if "__pycache__" not in p.parts and "migrations" not in p.parts
    ]


def main() -> int:
    args = sys.argv[1:]

    if not args:
        print("Usage: check_layer_imports.py <file.py> | --all", file=sys.stderr)
        return 2

    if args[0] == "--all":
        files = collect_python_files()
    else:
        target = Path(args[0])
        if not target.is_absolute():
            target = Path.cwd() / target
        if not target.exists():
            print(f"File not found: {target}", file=sys.stderr)
            return 2
        files = [target]

    all_violations: list[Violation] = []
    for f in files:
        all_violations.extend(check_file(f))

    if not all_violations:
        print(f"✓ No layer violations found ({len(files)} file(s) checked).")
        return 0

    print(f"\n✗ Layer violations found ({len(all_violations)}):\n")
    for v in all_violations:
        rel = v.file.relative_to(BACKEND_ROOT)
        print(f"  {rel}:{v.line}  [{v.layer}]  {v.reason}")
    print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
