const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const agents = [_]econ.micro.WalrasAgent{
        .{ .alpha = 0.75, .endowment = .{ 1, 4 } },
        .{ .alpha = 0.25, .endowment = .{ 4, 1 } },
    };
    const price = econ.micro.walrasPrice(&agents) catch unreachable;
    std.debug.print("clearing price={d:.6}\n", .{price});
}
