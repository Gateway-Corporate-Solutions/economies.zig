# Tutorial: a Solow transition path

Construct `macro.Solow`, call `steadyState`, and compare it with `simulate(initial, periods)`. Parameters are rates in decimal units and capital is effective-worker capital. The model is deterministic and allocates nothing.

The RBC example demonstrates the allocator-owning numerical path. The caller owns the value and policy buffers; the solver allocates only a temporary work buffer using the caller's allocator.
