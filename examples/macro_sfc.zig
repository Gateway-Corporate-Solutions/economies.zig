const std = @import("std");
const econ = @import("economies");
pub fn main(_: std.process.Init) void {
    const values = [_]f64{ -10, 8, 2, 5, -7, 2 };
    const valid = (econ.macro.SfcMatrix{ .rows = 2, .columns = 3, .values = &values }).validate(1e-12);
    std.debug.print("transaction-flow matrix reconciles={}\n", .{valid});
}
