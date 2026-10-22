#!/usr/bin/env python3
"""Reject a core checkout that restores the quarantined GLB material C API."""
import argparse
import re
from pathlib import Path
import sys

DECLARATION = re.compile(r'dust3d_glb_material_catalog_|Dust3DGlbMaterialCatalog')
IMPLEMENTATION = 'GlbMaterialCatalog.cc'

_CMAKE_SPACING = r'(?:\s|#[^\n]*(?:\n|$))*'
# Admit only the non-compiling companion guard; every other filename occurrence stays rejected.
NEGATIVE_CMAKE_GUARD = re.compile(
    r'^[ \t]*if' + _CMAKE_SPACING + r'\(' + _CMAKE_SPACING + r'EXISTS' + _CMAKE_SPACING
    + r'"[^"\r\n]*GlbMaterialCatalog\.cc"' + _CMAKE_SPACING + r'\)' + _CMAKE_SPACING
    + r'message' + _CMAKE_SPACING + r'\(' + _CMAKE_SPACING + r'FATAL_ERROR' + _CMAKE_SPACING
    + r'"(?:\\.|[^"\\])*"' + _CMAKE_SPACING + r'\)' + _CMAKE_SPACING
    + r'endif' + _CMAKE_SPACING + r'\(' + _CMAKE_SPACING + r'\)', re.MULTILINE | re.IGNORECASE)


def quarantine_violation(core):
    """Return a fail-closed diagnostic, or None when the selected core stays inside quarantine."""
    header = core / 'native/Engine/include/Dust3DBridge.h'
    if not header.is_file():
        return 'GLB catalog quarantine: public bridge header is missing'
    if DECLARATION.search(header.read_text(encoding='utf-8', errors='surrogateescape')):
        return 'GLB catalog quarantine (#69): unfinished C API must remain unavailable'
    if (core / 'native/Engine' / IMPLEMENTATION).exists():
        return 'GLB catalog quarantine (#69): unfinished implementation was restored'
    for name in ('Package.swift', 'CMakeLists.txt'):
        manifest = core / name
        if manifest.is_file():
            text = manifest.read_text(encoding='utf-8', errors='surrogateescape')
            if name == 'CMakeLists.txt':
                text = NEGATIVE_CMAKE_GUARD.sub('', text)
            if IMPLEMENTATION in text:
                return 'GLB catalog quarantine (#69): unfinished implementation was restored'
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core', type=Path, required=True)
    arguments = parser.parse_args()
    try:
        core = arguments.core.resolve(strict=True)
    except OSError as error:
        print(f'GLB catalog quarantine: core checkout is unavailable: {error}', file=sys.stderr)
        return 1
    violation = quarantine_violation(core)
    if violation:
        print(violation, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
