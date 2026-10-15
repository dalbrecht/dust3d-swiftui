# Native reference-image verification

Full `make ci` passes 191 tests, formatting, both native builds, coverage and Qt-free checks. Document coverage is 1691/1766 lines (95.75%); editor model 815/821 (99.27%); pure state 364/364 and undo 97/97 (100%). The new ImageIO/file/cache service measures 98/100 covered lines. This does not measure inherited C++ coverage or certify allocation-failure paths.

Fourteen new tests cover:

- PNG/JPEG/BMP/GIF/TIFF conversion, encoded limits, malformed input, dimensions/product limits before decode, and JPEG orientation baked into output dimensions.
- Existing PNG preview cache reuse without rewriting bytes, non-PNG rejection in the PNG slot, bounded file import and retained read causes, and oversized existing assets rejected from metadata while their archives remain unchanged.
- Controller import/removal/undo/redo, graph/geometry independence, transient visibility/opacity, malformed-asset preservation/removal/undo, and failed import preserving archive and redo.
- Qt positive-Y-down projection/dragging, image-height-normalized front/side placement, portrait/invalid aspect ratios and fitting the union of reference image and outlying nodes. Existing rotation expectations now verify correct screen-space clockwise/counterclockwise direction and exact undo.

Native QA used the isolated app bundle, leaving the main running apps and unsaved user work untouched:

1. Opened an asset-bearing three-node capsule and imported a generated 400×200 colored grid through the native raster chooser. In Front view, X=0.5 and Y=0.25/0.5/0.75 aligned with grid column 100 and rows 50/100/150. In Side view, Z=1 aligned with column 200 and the same Y rows. Visually inspected rendered nodes, image orientation and controls. The mesh remained 80 triangles.
2. Saved the archive. Independent parsing confirmed a Qt-compatible `asset` named `canvas.png`, exact original model XML, binary assets and unknown asset-header metadata. Import intentionally converts the source raster to PNG.
3. Changed opacity to 0.25, hid/showed the image, switched projection and saved. Whole-file byte comparison remained identical to the saved reference archive, demonstrating transient display settings.
4. Removed the reference, then exercised Undo/Redo. Node count and the 80-triangle mesh stayed intact. Undo restored the image; saving restored the exact prior archive bytes.
5. Closed and reopened the saved file. The image and 80-triangle mesh loaded, selection/history were empty, visibility was on and opacity reset to 0.5. Saving again preserved the complete file byte-for-byte, including the existing encoded PNG.
6. Opened a separate archive containing a malformed PNG-signature-only reference. It showed an explicit decode error while the graph and 80-triangle mesh remained available. Save preserved every original byte. Quit the QA app normally after saving its disposable fixtures.

No Qt GUI differential run, VoiceOver/oldest-supported-macOS certification, large-image latency budget or forced encoder/GPU allocation failure is claimed. Cropping, multiple-image composition, origin tools and full M2/later modeling parity remain pending. No core pin, C++ code or third-party package changed. See [the implementation decision](adr/0016-native-reference-images.md) for bounds, cache/publication policy and the intentional Y-axis convention correction.
