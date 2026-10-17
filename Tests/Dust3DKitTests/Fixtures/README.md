# Mesh loading fixtures

Capsule and Sword are existing MIT project fixtures. Capsule has three nodes and
one part; Sword comes from the inherited sword modeling example.

RoundedCrossing.ds3 is the synthetic MIT regression from dust3d-core issue #3,
independently encoded with Python on 2026-10-16. It contains five nodes, two parts
and three edges, with subdivision and rounded ends enabled. The previous pinned
core 685b68fb45405dabb4bb6f72c5b0e2598d4b9fdf fails to generate its mesh. Core
PR #4 fixes this case; the Swift regression checks successful complete loading,
finite positions/colors and unit normals within 0.001. Core tests additionally
check closed edge topology, translated/hard/subtraction variants and near-weld
separation; this Swift integration test does not prescribe triangulation order.

These binary archives have byte offsets and CRLF headers. Do not text-normalize.
