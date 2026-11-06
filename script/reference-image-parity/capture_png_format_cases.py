"""Small valid PNG format conformance cases for Qt image fitting, without a GUI."""
import base64
import hashlib
import json
from pathlib import Path
import struct
import zlib

from PySide6.QtCore import QSize, Qt, qVersion
from PySide6.QtGui import QImage


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def encode(width, height, depth, kind, rows, palette=None, transparency=None):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[kind]
    assert 1 <= width <= 512 and 1 <= height <= 8 and width * height <= 4096 and len(rows) == height
    packed = []
    for row in rows:
        assert len(row) == width * channels and all(0 <= s < (1 << depth) for s in row)
        if depth == 16:
            data = b"".join(struct.pack(">H", s) for s in row)
        elif depth == 8:
            data = bytes(row)
        else:
            bits = "".join(format(s, f"0{depth}b") for s in row)
            bits += "0" * (-len(bits) % 8)
            data = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
        packed.append(b"\0" + data)
    result = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, kind, 0, 0, 0))
    if palette is not None:
        result += chunk(b"PLTE", bytes(palette))
    if transparency is not None:
        result += chunk(b"tRNS", transparency)
    result += chunk(b"IDAT", zlib.compress(b"".join(packed))) + chunk(b"IEND", b"")
    assert len(result) <= 2048
    return result


def pixels(image, wide=False):
    result = []
    for y in range(image.height()):
        for x in range(image.width()):
            color = image.pixelColor(x, y)
            if wide:
                value = color.rgba64()
                result.append([value.red(), value.green(), value.blue(), value.alpha()])
            else:
                result.append(list(color.getRgb()))
    return result


assert qVersion() == "6.12.0"
sources = []
for depth in [1, 2, 4, 8, 16]:
    maximum = (1 << depth) - 1
    values = [0, maximum] if depth == 1 else [0, maximum // 2, maximum]
    key = maximum if depth == 1 else maximum // 2
    sources.append((f"gray{depth}-key", encode(len(values), 1, depth, 0, [values], transparency=struct.pack(">H", key))))
for depth in [1, 2, 4, 8]:
    sources.append((f"palette{depth}-alpha", encode(2, 1, depth, 3, [[0, 1]],
                    palette=[17, 83, 201, 201, 83, 17], transparency=bytes([0, 1]))))
for depth in [8, 16]:
    unit = 257 if depth == 16 else 1
    sources.append((f"rgb{depth}-key", encode(2, 1, depth, 2,
                    [[17 * unit, 83 * unit, 201 * unit, 201 * unit, 83 * unit, 17 * unit]],
                    transparency=struct.pack(">HHH", 17 * unit, 83 * unit, 201 * unit))))
    alpha = 1
    sources.append((f"rgba{depth}-low", encode(2, 1, depth, 6,
                    [[17 * unit, 83 * unit, 201 * unit, alpha, 201 * unit, 83 * unit, 17 * unit, 127 * unit]])))
    sources.append((f"graya{depth}-low", encode(3, 1, depth, 4,
                    [[17 * unit, alpha, 128 * unit, alpha, 255 * unit, alpha]])))
# The single-pixel painter first reads pixel() as RGBA8 even for RGBA64 sources.
for alpha in [1,128,129,256]:
    sources.append((f"rgba16-single-wide-a{alpha}",encode(1,1,16,6,[[4369,21331,51657,alpha]])))
# Named alpha boundaries exercise the single-pixel fill path and the vector tail.
for depth in [8, 16]:
    unit = 257 if depth == 16 else 1
    for alpha8 in [0, 1, 2, 64, 127, 128, 254, 255]:
        alpha = alpha8 * unit
        sources.append((f"rgba{depth}-single-a{alpha8}", encode(1, 1, depth, 6,
                        [[17 * unit, 83 * unit, 201 * unit, alpha]])))
    for width in [3, 5, 6, 7]:
        row = []
        for x in range(width):
            row += [17 * unit, 83 * unit, 201 * unit, unit if depth == 8 else 1]
        sources.append((f"rgba{depth}-tail{width}", encode(width, 1, depth, 6, [row])))
spatial = encode(3, 2, 8, 6, [[10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255],
                             [100, 110, 120, 255, 130, 140, 150, 255, 160, 170, 180, 255]])
sources += [
    ("spatial-palette2", encode(3,2,2,3,[[0,1,2],[3,0,1]],
        palette=[10,11,12,40,41,42,70,71,72,100,101,102])),
    ("spatial-gray2", encode(3,2,2,0,[[0,1,2],[3,0,1]])),
    ("spatial-gray8-key", encode(3,2,8,0,[[10,40,70],[100,130,160]],transparency=struct.pack(">H",40))),
]
sources.append(("extreme-downscale", encode(301,1,8,6,
    [[channel for x in range(301) for channel in (x%251,x%239,x%233,255)]])))
cases = []
for name, data in sources + [("spatial", spatial)]:
    image = QImage.fromData(data, "PNG")
    assert not image.isNull() and 1 <= image.width() <= 512 and 1 <= image.height() <= 8
    targets = [(image.width(), image.height()), (image.width() * 2, image.height() * 2)]
    if name.startswith("spatial") :
        targets += [(7, 5), (5, 3), (2, 2), (1, 1), (8, 8)]
    forced = [(769,3),(1,513)] if name == "spatial" else ([(1,3),(2,3)] if name == "extreme-downscale" else [])
    targets += forced
    for target in targets:
        mode = Qt.AspectRatioMode.IgnoreAspectRatio if target in forced else Qt.AspectRatioMode.KeepAspectRatio
        scaled = image.scaled(QSize(*target), mode)
        assert not scaled.isNull() and 1 <= scaled.width() <= 1024 and 1 <= scaled.height() <= 1024 and scaled.width()*scaled.height() <= 4096
        before = pixels(image)
        after = pixels(scaled)
        nearest = [before[((2 * y + 1) * image.height() // (2 * scaled.height())) * image.width()
                          + (2 * x + 1) * image.width() // (2 * scaled.width())]
                   for y in range(scaled.height()) for x in range(scaled.width())]
        cases.append({"name": name + "-" + "x".join(map(str, target)), "pngBase64": base64.b64encode(data).decode(),
                      "pngSHA256": hashlib.sha256(data).hexdigest(), "sourceSize": [image.width(), image.height()],
                      "target": target, "aspectMode": mode.name, "actualSize": [scaled.width(), scaled.height()],
                      "sourceFormat": image.format().name, "scaledFormat": scaled.format().name,
                      "decodedRGBA": before, "scaledRGBA": after, "decodedRGBA16": pixels(image, True),
                      "scaledRGBA16": pixels(scaled, True), "differsFromDecodedCenterNearest": nearest != after})
result = {"qt": qVersion(), "applicationCreated": False, "dust3dLoaded": False, "cases": cases}
output = Path(__file__).resolve().parents[2] / "outputs/qt-fast-scale-format-cases.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"qt": qVersion(), "caseCount": len(cases), "differences": [
    {"name": c["name"], "format": c["sourceFormat"], "size": c["actualSize"]}
    for c in cases if c["differsFromDecodedCenterNearest"]]}, indent=2))
