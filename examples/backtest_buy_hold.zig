const std = @import("std");
const econ = @import("economies");
pub fn main(init: std.process.Init) void {
    var portfolio = econ.backtest.Portfolio.init(init.gpa, 10_000) catch unreachable;
    defer portfolio.deinit();
    portfolio.applyFill(.{ .symbol = 1, .side = .buy, .quantity = 10, .price = 100, .fee = 5, .timestamp = 1 }) catch unreachable;
    std.debug.print("cash={d}, shares={d}\n", .{ portfolio.cash, portfolio.quantity(1) });
}
