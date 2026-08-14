# Contributing

economies.zig accepts small, falsifiable changes. Model contributions must include equations, assumptions, citations, invariants, a validation fixture, allocator and ownership documentation, and a public-interface example. Mechanism changes must retain a simple reference implementation for differential testing.

Run the complete local gate before opening a change:

```sh
./zigw fmt --check build.zig src examples bench
./zigw build all --summary all
./zigw build test -Doptimize=ReleaseSafe --summary all
```

Public API or model-semantics changes require a short design record under `docs/adr`. A model card must distinguish analytical validation, numerical validation, calibration, and empirical claims. Generated files, caches, and fetched packages do not belong in commits.
