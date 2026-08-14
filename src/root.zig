//! Deterministic economic simulation, exact accounting, and point-in-time backtesting.

pub const core = @import("core.zig");
pub const math = @import("math.zig");
pub const accounting = @import("accounting.zig");
pub const economics = @import("economics.zig");
pub const markets = @import("markets.zig");
pub const micro = @import("micro.zig");
pub const macro = @import("macro.zig");
pub const backtest = @import("backtest.zig");
pub const experiment = @import("experiment.zig");
pub const io = @import("io.zig");

test {
    _ = core;
    _ = math;
    _ = accounting;
    _ = economics;
    _ = markets;
    _ = micro;
    _ = macro;
    _ = backtest;
    _ = experiment;
    _ = io;
}
