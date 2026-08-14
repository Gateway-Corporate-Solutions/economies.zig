const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const signal = econ.backtest.movingAverageSignal(&.{ 90, 95, 100, 105 }, 2, 4) catch unreachable;
    std.debug.print("signal={s}\n", .{@tagName(signal)});
}
