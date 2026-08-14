# MVP validation report

Date: 2026-08-13  
Compiler: Zig 0.16.0  
Local target: x86_64 Linux  
Optimization modes verified: Debug, ReleaseSafe, ReleaseFast

## Determinism and core

- Equal-time events preserve insertion order; cancellation and rescheduling retain deterministic sequence semantics.
- Empty and populated scheduler checkpoints preserve event IDs and sequence counters.
- A replay bundle restores model state, scheduler state, and PRNG state together.
- Named random streams reproduce independently of construction order.
- Observer presence does not change model output or replay hash.

## Accounting and markets

- Unbalanced and cross-currency journal operations fail; checked integer overflow fails.
- Cash transfers and asset settlement conserve postings and lots.
- Loan maturity reconciles lender and borrower accounts.
- Limit, market, IOC, GTC, cancel, replace, partial fill, and price-time priority fixtures pass.
- A separate sorted matcher agrees with the reference matcher over 500 seeded randomized orders.
- First-price, second-price, English, Dutch, and double-auction fixtures conserve allocations and resolve ties deterministically.

## Micro and macro

- Cobb-Douglas demands exhaust budgets; CES and production fixtures match closed forms.
- Partial equilibrium, Cournot, Bertrand, normal-form Nash, replicator, Walrasian, bilateral, and trading-post fixtures meet analytical or conservation conditions.
- Solow simulation converges to its analytical steady state within the declared discrete-time tolerance.
- RBC value iteration meets the Bellman residual threshold, produces a monotone policy, and yields a decaying AR(1) impulse path.
- SFC transaction rows and columns balance; sector flows reconcile to stocks.
- The heterogeneous economy preserves exact nominal stocks through 100 periods across 100 seeded replications while exercising employment, benefits, wages, taxes, consumption, bank credit, debt service, repayment, inventories, and adaptive prices.

## Backtesting and experiments

- Future access and nonmonotonic source data fail explicitly.
- Bar limits cannot fill outside observed ranges; quote execution enforces timestamp latency and bid/ask spread.
- Fees and slippage cannot improve a fixed execution path.
- Buy-and-hold reconciles fills, fees, dividends, splits, liquidation, and the shared double-entry cash account.
- Strategies receive immutable views and derive position state from confirmed holdings, not emitted intents.
- Settlement delays, walk-forward partitions, drawdown/return metrics, trade metrics, and market-making quote fixtures pass.
- A 1,000-run experiment resumes from a partial result set without recomputation and produces byte-equivalent ordered results.

## Commands

```sh
./zigw fmt --check build.zig src examples bench
./zigw build all -Doptimize=ReleaseSafe --summary all
./zigw build test -Doptimize=ReleaseFast --test-timeout 30s --summary all
```

Local validation does not substitute for the configured macOS and Windows CI jobs, independent economic review, independent reproduction, or empirical validation of stylized models.
