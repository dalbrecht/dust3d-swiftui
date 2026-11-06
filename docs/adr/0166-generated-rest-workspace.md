# ADR 0166: Window-owned generated rest workspace

Status: Experimental local-core integration, Apple #367 / M5 #144.

Qt BoneManageWidget creates its rest model pane with camera controls and a
minimum height (application/sources/bone_manage_widget.cc200-225). Native rest
inspection previously lived only in a compact inspector. Provide a resizable
central split and explicit Model/Generated Rest presentation without duplicating
native work when the inspector and workspace exchange the same logical preview.

One root-owned GeneratedRigPreviewSession owns generation/display tasks, selection,
retry epochs, wireframe and MeshCameraState. Views borrow it through the environment;
a standalone view has its own fallback. Child disappearance does not cancel a
shared session; window shutdown permanently stops it. New sources validate full
immutable bytes before loading, then actor snapshot identity/revision permits cheap
input checks without archive encoding per pointer event. New sources reset the
camera; palette, selection and presentation changes reuse generated data and camera.

A template name supplied by a view seeds a new document/template source only.
Preserve the explicit template choice across revisions of the same document and
exact UTF-8 rig type, including workspace assignment/settings edits. Clear the
generated-joint override for each regenerated rig; a new document/type does not
inherit the stored template choice. Explicit template
clicks control later changes, including clearing a generated-joint override when
clicking the already-selected template. Retry and menu actions check captured
source epochs. Raw viewport input additionally checks its captured presentation
UUID, preventing obsolete surfaces from writing a newer camera even after a
presentation round trip. Pointer updates do not invalidate surrounding SwiftUI;
discrete controls invalidate through the owner's revision. Legacy viewport APIs
retain view ownership when no camera owner is supplied.

Focused scene actions route View camera commands exclusively to the visible
workspace. An unavailable rest surface cannot fall back to the model camera.
Automatic orbit is unsupported in rest mode; the model's saved preference is
retained. Toolbar Fit and display setters capture a presentation UUID and reject stale
callbacks even after a mode round trip. Focused display actions route Wireframe
from both menu and toolbar to the visible preview; Model Colors is unavailable in
rest mode rather than changing the hidden ordinary model.

Pure copied-data regressions exercise ownership, late selections, source and
presentation replacement, retries and camera controls without creating NSView or
Metal devices. SwiftUI focus, physical camera interaction, VoiceOver and rendered
layout remain manual acceptance gaps. Model/Bones/Weights visibility with fixed
combined-stream framing and 3D picking remain subsequent work. No pose controller,
production core pin change or full Qt/HIG parity claim is part of this slice.
