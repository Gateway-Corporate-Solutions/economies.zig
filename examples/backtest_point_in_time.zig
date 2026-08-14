const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const events = [_]econ.backtest.MarketEvent{.{ .trade = .{ .timestamp = 1, .symbol = 1, .price = 100, .quantity = 1 } }};
    var feed = econ.backtest.PointInTimeFeed{ .events = &events };
    const event = (feed.next() catch unreachable).?;
    std.debug.print("visible timestamp={d}\n", .{econ.backtest.eventTimestamp(event)});
}
