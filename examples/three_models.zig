const std = @import("std");
const economies = @import("economies");

pub fn main(_: std.process.Init) void {
    const MicroSlice = struct {
        demand_x: f64 = 0,
        pub fn step(self: *@This(), _: economies.core.Tick) !void {
            self.demand_x = (try (economies.micro.CobbDouglas{ .alpha = 0.4 }).demand(100, 2, 4))[0];
        }
    };
    const MacroSlice = struct {
        capital: f64 = 0.5,
        pub fn step(self: *@This(), _: economies.core.Tick) !void {
            self.capital = (economies.macro.Solow{}).step(self.capital);
        }
    };
    const BacktestSlice = struct {
        signal: economies.backtest.OrderSide = .sell,
        pub fn step(self: *@This(), _: economies.core.Tick) !void {
            self.signal = try economies.backtest.movingAverageSignal(&.{ 90, 95, 100, 105 }, 2, 4);
        }
    };
    var micro = MicroSlice{};
    var macro = MacroSlice{};
    var backtest = BacktestSlice{};
    economies.core.runSteps(&micro, economies.core.NullStepObserver{}, 1) catch unreachable;
    economies.core.runSteps(&macro, economies.core.NullStepObserver{}, 100) catch unreachable;
    economies.core.runSteps(&backtest, economies.core.NullStepObserver{}, 1) catch unreachable;
    std.debug.print("micro demand={d:.2} macro capital={d:.3} backtest signal={s}\n", .{ micro.demand_x, macro.capital, @tagName(backtest.signal) });
}
