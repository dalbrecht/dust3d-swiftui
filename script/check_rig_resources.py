#!/usr/bin/env python3
"""Verify an installed SDK bundle against the reviewed source provenance."""
import hashlib
import json
from pathlib import Path
import sys


def verify(bundle):
    source = Path(__file__).resolve().parents[1] / 'Sources/Dust3DKit/RigTemplates'
    expected = json.loads((source / 'provenance.json').read_text())
    templates = bundle / 'RigTemplates'
    if (templates / 'provenance.json').read_bytes() != (source / 'provenance.json').read_bytes():
        raise ValueError('Rig template provenance differs from the reviewed source')
    if (templates / 'LICENSE').read_bytes() != (source / 'LICENSE').read_bytes():
        raise ValueError('Rig template MIT attribution is missing or changed')
    for entry in expected['resources']:
        name = Path(entry['path']).name
        with (templates / name).open('rb') as stream:
            data = stream.read(16385)
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Rig template differs from pinned source: ' + name)
    print(str(bundle) + ': seven pinned rig resources and MIT provenance verified')


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, IndexError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
