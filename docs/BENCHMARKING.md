# Benchmark protocol

Record CPU, operating system, Zig 0.16.0, target, optimization mode, allocator, root seed, configuration, input size, elapsed time, and peak memory. Report setup, I/O, and model execution separately. Debug, ReleaseSafe, and ReleaseFast are distinct series. Optimization changes require before/after profiles and must pass all invariant and differential tests.

The initial harness measures named-stream generation and exists to stabilize metadata and measurement procedure. Event, journal, order-book, agent, macro, backtest, and experiment benchmarks are added alongside their optimized implementations.
