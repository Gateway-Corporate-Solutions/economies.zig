# economies.zig

Auditable economic simulations and backtests in Zig with exact accounting and deterministic replay.

This development release targets Zig 0.16.0 and has no external dependencies. Its public `economies` module combines a deterministic event kernel, checked double-entry accounting, economic entities and contracts, market mechanisms, validated micro/macro reference models, point-in-time backtesting, experiment grids, CSV schemas, examples, and benchmarks.

## Current capabilities

- Stable typed IDs, integer clocks, named random streams, stable equal-time ordering, cancellation, rescheduling, checkpoints, replay hashes, manifests, and observer isolation.
- Checked minor-unit money, typed asset quantities and tick prices, multi-currency journals, asset/cash settlement, loans, portfolios, and conservation tests.
- Cobb-Douglas and CES preferences, production and cost functions, partial and Walrasian equilibrium, Cournot and Bertrand competition, normal-form games, replicator dynamics, bilateral exchange, trading posts, standard auctions, and reference/optimized limit order books.
- Solow-Swan, RBC value-function iteration and impulse paths, stock-flow-consistent matrices and sector stocks, a deterministic heterogeneous-agent economy, and policy rules.
- Bars, quotes, trades, rates, corporate actions, symbol metadata, calendars, immutable strategy views, latency, spread, slippage, fees, settlement, ledger-backed P&L, performance metrics, walk-forward partitions, and four reference strategy primitives.
- Deterministic parameter grids, resumable replications, confidence intervals, and optimizer-independent calibration hooks.

## Build and verify

```sh
./zigw fmt --check build.zig src examples bench
./zigw build all --summary all
./zigw build test -Doptimize=ReleaseSafe --test-timeout 30s --summary all
```

Named steps are `test`, `examples`, `bench`, `docs`, `run`, and `all`. The installed CLI is `zig-out/bin/economies`; generated API documentation is under `zig-out/docs`.

## Use as a dependency

After adding a release archive with `zig fetch --save <immutable-release-url>`, expose the module to your application:

```zig
const dependency = b.dependency("economies", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("economies", dependency.module("economies"));
```

Then import the stable root:

```zig
const econ = @import("economies");

const model = econ.macro.Solow{};
const steady_state = model.steadyState();
```

Until the first immutable release URL exists, use a `.path` dependency pointing at this checkout. The package manifest ships only the public source, examples, benchmark, documentation, license, and project policies.

## Contracts

Operations that allocate accept or retain an explicit allocator and provide `deinit`. Observers and backtest strategies receive immutable views. Exact values never convert to floating point implicitly. Discrete state, event, and ledger replay is exact on one target; cross-target floating-point comparisons use model-specific tolerances. Backtests prevent future event access but cannot repair survivorship bias or inaccurate vendor data.

See `docs/adr/0001-foundation.md`, `docs/MODEL_CARD_TEMPLATE.md`, the three tutorials under `docs/tutorials`, and the validation fixtures embedded beside each implementation.

## Toolchain and license

The `zigw` launcher uses Zig 0.16.0 from `PATH` or the workspace-local toolchain. Caches and build products are isolated and ignored by Git. economies.zig is licensed under Apache-2.0.
