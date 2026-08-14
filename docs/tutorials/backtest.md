# Tutorial: point-in-time buy and hold

Create a chronologically sorted `PointInTimeFeed`. Only events returned by `next` are visible through `eventAt`; future access fails with `error.FutureData`, and backward timestamps fail with `error.NonMonotonicData`. Return `OrderIntent` values to `Broker`, then apply accepted fills and corporate actions to `Portfolio`.

Bar fills expose their assumptions: market orders use the next visible open, limits require a compatible high/low range, and no intrabar sequence is inferred. Quote fills use the visible bid or ask and enforce configured latency.
