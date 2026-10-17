# ADR 0040: Part shape modifier flags

Status: Accepted. Tracks #62.

Expose inherited subdivision (`subdived`), chamfer (`chamfered`), rounded ends
(`rounded`), extra rings (`interpolated`) and hard joins (`hard`) through a typed
part command, immutable metadata and native part inspector controls. Extra rings
default to true; the other flags default to false. Subdivision/chamfer alter the
cross-section template, not a new surface-subdivision algorithm.

`DocumentPart.modifierValue(_:)` returns a known source/default boolean or nil
for unsupported source spellings. Recognize exact inherited true spellings and
explicit false/False/0. Preserve unknown values unless the user explicitly chooses
On or Off. Empty interpolation is unavailable: the Qt importer treats an explicit
empty value as false while the pinned core treats it as enabled. Do not silently
resolve that compatibility difference. Other empty flags mean false in both.

An actual edit writes the nondefault flag or removes the attribute when restoring
its default. A semantic no-op retains original XML spellings and archive bytes,
and preserves redo. Validate part identities through the existing document boundary.
Keep unrelated metadata, source nodes/edges, component hierarchy and assets intact.
Part/axis locks constrain node transforms; as with the inherited modifier setters,
these explicit part metadata controls remain usable for hidden, locked and disabled
parts without unlocking or moving their nodes.

The document/controller foundation is delivered before the native inspector.
The inspector follow-up will use native toggles for known values and an explicit
On/Off picker for unsupported values until replaced. Each choice uses the
serialized actor/history/preview path and regenerates without resetting camera or
part selection. No C++ adapter change is needed in the Apple repository.

Test every flag's defaults, unknown values, exact history, no-ops and source/data
preservation. Verify real geometry for each shape flag, all sixteen four-flag
combinations, and hard-join seam changes on a non-coplanar intersecting fixture.
A rounded crossing fixture exposed an inherited boolean failure, tracked in
[core issue 3](https://github.com/dalbrecht/dust3d-core/issues/3). The core fix landed in
[core PR 4](https://github.com/dalbrecht/dust3d-core/pull/4), with a separate exact-pin
Apple dependency update. The modifier stage must be validated against that pin.
Successful fixture coverage does not establish complete Qt differential parity.
