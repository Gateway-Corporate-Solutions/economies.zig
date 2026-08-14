const std = @import("std");
const econ = @import("economies");
pub fn main(init: std.process.Init) void {
    const grid = [_]f64{ 0.2, 0.5, 1.0, 1.5, 2.0 };
    var values = [_]f64{0} ** grid.len;
    var policy = [_]usize{0} ** grid.len;
    const residual = (econ.macro.Rbc{}).solve(init.gpa, &grid, &values, &policy, 1e-7, 2_000) catch unreachable;
    std.debug.print("Bellman residual={d}\n", .{residual});
}
