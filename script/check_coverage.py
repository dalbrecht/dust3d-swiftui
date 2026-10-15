"""Require real library coverage, including every file and the pure undo domain."""

import json
from pathlib import Path
import sys


root = Path(__file__).resolve().parent.parent
report = json.load(sys.stdin)
files = {
    Path(item["filename"]).resolve(): item["summary"]["lines"]
    for section in report["data"]
    for item in section["files"]
}
groups = [
    ("Swift mesh library", list((root / "Sources/Dust3DKit").glob("*.swift")), 95),
    ("Document library", list((root / "Sources/Dust3DDocument").glob("*.swift")), 95),
    ("Editor model", list((root / "Sources/Dust3DEditorModel").glob("*.swift")), 95),
    ("Pure editor state", [root / "Sources/Dust3DEditorModel/EditorState.swift"], 100),
    ("Pure undo domain", [root / "Sources/Dust3DDocument/DocumentHistory.swift"], 100),
]
for name, paths, minimum in groups:
    if not paths or any(path not in files for path in paths):
        raise SystemExit(f"Missing coverage input for {name}")
    count = sum(files[path]["count"] for path in paths)
    covered = sum(files[path]["covered"] for path in paths)
    if count == 0 or covered * 100 < count * minimum:
        raise SystemExit(f"{name}: {covered}/{count} lines, requires {minimum}%")
    print(f"{name}: {covered}/{count} lines; required {minimum}%")
