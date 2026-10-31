# Historical hollow-thickness reference

This is an investigative harness, not native runtime code or an imported-model fixture. `main.cpp` builds a two-node straight tube with a four-corner square cut, radius 1, and node positions (0, 0, 0) and (0, 0, 2). `results.log` records the measured output. Face degeneracy uses squared Newell normal length below 1e-12; edge incidence uses vertex indices, so it cannot establish geometric manifoldness at coincident vertices. Pair-error checks rely on the historical builder's observed outer-then-inner ordering and source node IDs for this fixture.

Source: `thirdparty/nodemesh` from dust3d-core commit `9ed4c29b39a805a08eee671c74cba23d329a2556` (original hollow parameter implementation). The builder source was unchanged; SHA-256 of `nodemesh/builder.cpp` was `bdae407ae29d24eec851511a2381de75461a31249d2e9c6f57643610e15b801d`. `compatibility.patch` contains the complete changes needed in auxiliary historical sources to build against Qt 6.12.0 and CGAL 6.2.1: current CGAL named subdivision parameters and experimental namespace, and Qt's namespaced stream terminator. These adaptations do not establish equivalence for other paths.

Example reproduction in an isolated directory with those dependencies available:

```sh
git archive 9ed4c29b39a805a08eee671c74cba23d329a2556 thirdparty/nodemesh | tar -x
cd thirdparty/nodemesh
patch -p1 < /path/to/compatibility.patch
cd ../..
xcrun clang++ -std=c++17 -O0 -I /opt/homebrew/include -L /opt/homebrew/lib \
  -I thirdparty/nodemesh $(pkg-config --cflags Qt6Core Qt6Gui) \
  /path/to/main.cpp thirdparty/nodemesh/nodemesh/{builder,stitcher,wrapper,box,combiner,cgalmesh,misc,positionkey}.cpp \
  $(pkg-config --libs Qt6Core Qt6Gui) -lmpfr -lgmp -o hollow-reference
./hollow-reference
```

This one fixture cannot establish UV behavior, rounded or tapered topology, imported-model behavior, or safe semantics for out-of-range values. In particular, indexed edge incidence of two at thickness 1 does not make the collapsed inner faces nondegenerate.
