const std = @import("std");
const economies = @import("economies");

pub fn main(_: std.process.Init) void {
    const steady = economies.macro.Solow.steadyState(.{});
    std.debug.print("economies.zig 0.1.0-dev.1\nSolow steady-state capital: {d:.6}\n", .{steady});
}
