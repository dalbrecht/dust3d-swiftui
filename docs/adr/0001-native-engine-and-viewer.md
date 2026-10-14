# ADR 0001: Qt-free engine and native macOS viewer

Status: Accepted for the local prototype.

Keep the inherited Dust3D C++17 engine and vendored geometry dependencies. SwiftPM declares separate targets for triangle intersection, AutoRemesher, the modeling core, the C bridge, the Swift document service, and the SwiftUI executable. Native targets do not compile or link `application/`, Qt, OpenGL, or the Qt application controllers.

The C bridge accepts complete `.ds3` bytes, validates the archive and snapshot, and returns an opaque owner of expanded triangle vertices. Swift copies position, normal, and color buffers before destroying the owner. All exceptions become a status and diagnostic. A process-wide mutex serializes inherited engine entry points because UUID generation and engine globals have not been audited for concurrent use.

The Swift file service is an actor. File reads and generation run outside the main actor; the observable viewer store and Metal rendering stay on the main actor. Superseded loads cannot replace newer results. Cancellation is cooperative before and after generation; an in-progress C++ generation is not interruptible.

Use SwiftUI for scenes, file selection, commands, progress, errors, and status. A small `NSViewRepresentable` hosts `MTKView`; its AppKit subclass handles pointer/keyboard camera input. Rendering uses copied immutable geometry, depth testing, smooth normals, component vertex colors, and bounds-based camera fitting. The camera changes only presentation, never source geometry.

This milestone is a read-only procedural geometry viewer. It does not save or edit documents, display reference images, bake/display texture maps, import embedded GLB geometry, export models, or play animations. Imported geometry fails explicitly instead of presenting a partial model. Image assets and procedural surface detail settings produce an untextured-preview warning. Transparent materials are shown opaque.

SwiftPM is the declarative project spec. The local run script stages an ad-hoc signed `.app` bundle with document type registration and Metal resources outside File Provider folders, and delivers a ZIP archive in `dist/`. File Provider can automatically add Finder metadata to app/resource bundles, invalidating signatures even after `xattr -cr`; the ZIP prevents those changes inside the sealed app. No Apple Developer Team ID is required for local development. Distribution signing, sandbox entitlements, notarization, and an XcodeGen/Tuist app project can be added when distribution is in scope.

The inherited `.ds3` reader is not used as a trust boundary: the adapter first checks magic/version, header bounds, required attributes, unsigned offsets, payload bounds, duplicate names, model count, XML closing tags/depth, finite coordinates, identifiers, and graph references. Limits are 256 MiB per archive, 1 MiB header XML, 16 MiB model XML, 128 XML nesting levels, 10,000 nodes/components, 20,000 edges, and five million output triangles. These limits bound parsing and output transfer; they do not provide a hard CPU/memory limit inside inherited geometry algorithms. Hostile-document process isolation is future work.
