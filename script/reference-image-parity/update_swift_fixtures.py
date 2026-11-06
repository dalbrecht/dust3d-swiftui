"""Refresh own encoded PNG reference data, never a rendered UI baseline."""
import json
from pathlib import Path
import sys
cases=json.loads(Path(sys.argv[1]).read_text())["cases"]
p=Path(sys.argv[2])
s=p.read_text().split("    private static let fixtures: [Fixture] = [")[0]
parts=[s,"    private static let fixtures: [Fixture] = [\n"]
for c in cases:
    w,h=c["actualSize"]
    flat=[v for pix in c["scaledRGBA"] for v in pix]
    parts.append("        Fixture(\n            name: "+json.dumps(c["name"])+",\n            png: "+json.dumps(c["pngBase64"])+",\n            sha256: "+json.dumps(c["pngSHA256"])+",\n            width: "+str(w)+", height: "+str(h)+",\n            expected: [\n")
    for i in range(0,len(flat),16): parts.append("                "+", ".join(map(str,flat[i:i+16]))+",\n")
    parts.append("            ]),\n")
parts.append("    ]\n}\n")
p.write_text("".join(parts))
print("Frozen cases:",len(cases))
