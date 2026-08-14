const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const demand = (econ.micro.CobbDouglas{ .alpha = 0.4 }).demand(100, 2, 4) catch unreachable;
    std.debug.print("x={d:.2}, y={d:.2}\n", .{ demand[0], demand[1] });
}
