# Roadmap implementation ledger

Updated: 2026-08-13

The code-level MVP foundation is implemented and locally validated. The public-release roadmap is not closed because several gates require infrastructure or people outside this workspace. This ledger avoids treating configured CI, planned review, or written policy as completed evidence.

| Roadmap area | Status | Evidence or remaining gate |
| --- | --- | --- |
| Phase 0: charter and package | Implemented locally | Name, Apache-2.0, governance, contribution/security/citation files, strict manifest, public module, design record, model cards, CI, examples, docs, bench, and all steps. |
| Phase 1: reproducible vertical slice | Implemented locally | Shared discrete/event runners, named RNG, scheduler, observers, manifests, CSV, exact money, journals, replay bundle, and three model-family slices. Debug and ReleaseSafe pass locally; macOS/Windows jobs are configured but unrun here. |
| Phase 2: economic kernel | Implemented baseline | Typed quantities/prices/assets, contracts, portfolios, settlement, checked math, statistics, interpolation, optimization, schemas, and invariant errors. Broader currency/contract catalogs remain post-baseline expansion. |
| Phase 3: micro suite | Implemented baseline | Preferences, production, costs, partial/Walrasian equilibrium, oligopoly, games, replicator dynamics, bilateral/trading post, five auction forms, and differential-tested reference/sorted order books. |
| Phase 4: macro suite | Implemented baseline | Solow, RBC VFI and impulse path, SFC matrices/stocks, policy rule, and 100-replication heterogeneous economy with labor, goods, credit, fiscal, and price dynamics. Domain review and external reference-series comparison remain. |
| Phase 5: backtesting suite | Implemented baseline | Point-in-time event feed, bar CSV, calendar, immutable strategies, broker fills, costs, latency, settlement, ledger-backed portfolio, actions, metrics, partitions, experiment integration, and four strategy primitives. Vendor datasets are intentionally outside scope. |
| Phase 6: experiments and performance | Implemented serial baseline | Deterministic/resumable grids, streaming statistics, confidence intervals, calibration hook, replay bundle, sorted data path, benchmark harness, and results. Actual parallel execution remains post-MVP as originally constrained by frozen serial semantics. |
| Phase 7: release hardening | Partially complete | API docs, guides, tutorials, ten examples, validation report, performance baseline, policies, changelog, citation, and package allowlist exist. Immutable hosting/tag, fresh remote fetch, cross-platform CI evidence, two independent reproductions, and external reviews cannot be completed inside this workspace. |

## External release blockers

1. Publish the repository and immutable source archive, replace the development citation metadata with its canonical URL and archive DOI if available, then run a fresh-cache `zig fetch --save` consumer test.
2. Execute the configured Zig 0.16.0 matrix on Linux, macOS, and Windows in Debug and ReleaseSafe.
3. Obtain one economics-domain review and one Zig maintainer review of public semantics and validation tolerances.
4. Have two users who did not implement the package reproduce one micro, one macro, and one backtest example.
5. Address findings, freeze the supported public surface, set the changelog release date, and create an immutable `v0.1.0` tag.

Until those gates produce evidence, the package is an MVP release candidate rather than a completed public MVP.
