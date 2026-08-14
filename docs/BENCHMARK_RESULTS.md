# Initial benchmark results

Date: 2026-08-13  
Compiler: Zig 0.16.0  
Target: x86_64 Linux, ReleaseSafe  
Environment: isolated workspace; host CPU model unavailable

| Benchmark | Work | Elapsed |
| --- | ---: | ---: |
| Named stream derivation | 100,000 streams | 1,826,703 ns |
| Reference event queue | 5,000 enqueue + 5,000 dequeue | 11,252,647 ns |
| Double-entry journal | 10,000 transactions | 300,196 ns |
| Sorted order book | 20,000 orders, 9,523 trades | 4,052,116 ns |
| Solow transition | 1,000,000 steps | 45,993,626 ns |

These numbers establish a reproducible baseline, not a cross-machine performance claim. Checksums and final state are emitted by the harness to prevent dead-code elimination. Re-run `./zigw build bench -Doptimize=ReleaseSafe` on named reference hardware before publishing release performance claims.
