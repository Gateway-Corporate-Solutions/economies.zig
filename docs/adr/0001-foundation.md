# ADR 0001: deterministic economic foundation

Status: accepted

- Time is an unsigned integer tick. Event order is `(tick, insertion_sequence)`.
- Entity IDs are typed values and never pointers or collection indexes.
- Randomness derives named child streams from a root seed. No global PRNG is exposed.
- Money uses checked signed minor units, security quantities use integer lots, exchange prices use ticks, and continuous model mathematics defaults to `f64`.
- Models own their state. The common runner requires behavior by compile-time contract and does not impose a base-agent hierarchy.
- Scheduled payloads are model-specific tagged unions. The reference queue favors legible semantics over asymptotic performance until differential tests exist.
- Checkpoints include model state, queue state, stream state, schema versions, and accounting state. On-target discrete replay is exact.
- Public allocating operations accept an allocator and return ownership explicitly.
