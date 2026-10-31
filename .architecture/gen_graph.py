#!/usr/bin/env python3
"""Regenerates .architecture/graph.json from Sources/ScreenCapture.

Nodes = Swift source files (with the top-level types they declare).
Edges = file A references a type declared in file B (word match, comments stripped).
Usage: python3 .architecture/gen_graph.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ScreenCapture"
OUT = Path(__file__).resolve().parent / "graph.json"

DECL = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|final|private|fileprivate)\s+)*"
    r"(?:class|struct|enum|protocol|actor)\s+(\w+)",
    re.M,
)
EXT = re.compile(r"^(?:private\s+|fileprivate\s+)?extension\s+(\w+)", re.M)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def main() -> None:
    files = sorted(SRC.rglob("*.swift"))
    sources = {f: strip_comments(f.read_text()) for f in files}
    owner: dict[str, Path] = {}
    nodes = []
    for f, text in sources.items():
        # Only non-private top-level/nested types are reachable from other files.
        types = [t for t in DECL.findall(text)]
        public_types = []
        for t in types:
            if re.search(rf"^\s*(?:private|fileprivate)\s+(?:final\s+)?(?:class|struct|enum)\s+{t}\b", text, re.M):
                continue
            public_types.append(t)
            owner.setdefault(t, f)
        rel = str(f.relative_to(SRC))
        nodes.append({
            "id": rel,
            "layer": rel.split("/")[0] if "/" in rel else "Entry",
            "loc": text.count("\n"),
            "types": public_types,
            "extends": sorted(set(EXT.findall(text))),
        })

    edges = []
    for f, text in sources.items():
        targets: dict[Path, set[str]] = {}
        for t, g in owner.items():
            if g == f:
                continue
            if re.search(rf"\b{re.escape(t)}\b", text):
                targets.setdefault(g, set()).add(t)
        for g, ts in sorted(targets.items()):
            edges.append({"from": str(f.relative_to(SRC)), "to": str(g.relative_to(SRC)), "via": sorted(ts)})

    OUT.write_text(json.dumps({
        "root": "Sources/ScreenCapture",
        "generatedBy": ".architecture/gen_graph.py",
        "nodes": nodes,
        "edges": edges,
    }, indent=1) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(nodes)} nodes, {len(edges)} edges")


if __name__ == "__main__":
    main()
