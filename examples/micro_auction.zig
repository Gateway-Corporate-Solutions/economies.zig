const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const result = econ.markets.secondPrice(&.{
        .{ .bidder = 1, .value = 100, .sequence = 0 },
        .{ .bidder = 2, .value = 80, .sequence = 1 },
    }).?;
    std.debug.print("winner={d}, payment={d}\n", .{ result.winner, result.payment });
}
