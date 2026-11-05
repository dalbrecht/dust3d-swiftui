# ADR 0140: Archive the signed app tree without metadata sidecars

## Context

Canonical ditto archive creation generated ten AppleDouble files in the isolated
hollow QA ZIP after metadata cleanup and signing. These files were absent from
the signed input tree. Issue #329 tracks the canonical packaging correction.

## Decision

Port the existing development helper from commit b3ee34d0. The helper enumerates
actual files/directories/symbolic links using lstat, streams regular file bytes,
and preserves UNIX type/mode bits and exact link targets. It never reads link
referents or filesystem-only xattrs. Legitimate signed `._` resources are retained;
no filename pattern is discarded. Unsupported special entries fail explicitly.

An adjacent temporary archive replaces the destination atomically after success.
Invalid roots, recursive destinations and read failures preserve an existing ZIP.
Build, running-process checks, resource assembly, signing and timestamp order remain
in the canonical path. This changes neither the production core pin nor dependencies.

## Verification scope

Six disposable-tree tests cover exact entries/payloads, permissions, empty folders,
attached xattrs, legitimate sidecar-style names, framework/outside/dangling links,
invalid destinations and failure cleanup. The canonical bundle-rebuild gate now
compares ZIP entries and extracted bytes/types/modes/links with the complete signed
Editor, Viewer and isolated QA trees, then verifies extracted signatures. These are
build-only checks; no native application or protected QA process is controlled.
