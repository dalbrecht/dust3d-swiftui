# Two selected-node connection (#349)

Qt core b475c730 SkeletonGraphicsWidget::hasTwoDisconnectedNodesSelection and
connectSelected expose Connect for two selected eligible nodes. Native already
had the joining algorithm and a single-node Connect to menu, but GroupInspector
lacked the direct pair workflow. Shared NodeConnectionControls now serve the
selection inspector and Canvas menu. Cross-part choices explicitly identify the
settings owner; same-part connections use the same captured action directly.
Duplicate part/node names are disambiguated by the actual endpoint identity.

Regression evidence:

- Initial model/session build failed because NodeConnectionTarget and the new
  commands did not exist. A first implementation run caught two unnecessary try
  markers in test calls; those were corrected before the seven initial contracts
  passed. No failed compilation is counted as a passing test run.
- Controller contracts then failed on the missing action/availability API. The
  ownership-label regression failed compilation before its presenter existed.
- All 14 focused contracts passed: ten model/session and four controller tests.
  They verify each settings owner, one-step exact Undo/Redo, preserved selection,
  other-window independence, same-part chain closure, eligibility/cardinality/
  mixed-edge/read-only/degree handling, source-byte owner/part identity, old
  selection and constraint ABA, document Undo/replacement, unavailable/wrong-owner
  actions, stop, one document publication and cooperative cancellation. Original
  document errors retain their type and leave bytes/history unchanged.
- The ordinary 20,000-edge capacity case is bounded metadata only; it never
  reaches preview, texture, import, animation or native generation. All new Store
  tests inject blocked implementations for every native service.

The required full committed production-pin make ci gate is separate from focused
results and must pass before publication. The existing PartJoiningTests continue
to cover orientation, asset/unknown XML retention, component handling and profile
rollback in the reused document algorithm. New tests do not imply independently
accepted Qt geometry, physical menu/inspector/pointer/keyboard or VoiceOver flows.
Current AX observation fails calibration; it is not used as a substitute for
those acceptance gates. Production core pin and all quarantines remain unchanged.
