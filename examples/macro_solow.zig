const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const model = econ.macro.Solow{};
    std.debug.print("analytical={d:.6}, simulated={d:.6}\n", .{ model.steadyState(), model.simulate(0.5, 2_000) });
}
