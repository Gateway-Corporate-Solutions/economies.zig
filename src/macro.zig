//! Analytical growth, RBC, stock-flow-consistent, and heterogeneous-agent macro models.

const std = @import("std");
const core = @import("core.zig");

pub const Solow = struct {
    savings: f64 = 0.2,
    depreciation: f64 = 0.05,
    population_growth: f64 = 0.01,
    technology_growth: f64 = 0.02,
    alpha: f64 = 0.33,

    pub fn steadyState(self: Solow) f64 {
        return std.math.pow(f64, self.savings / (self.depreciation + self.population_growth + self.technology_growth), 1.0 / (1.0 - self.alpha));
    }
    pub fn step(self: Solow, capital: f64) f64 {
        return (self.savings * std.math.pow(f64, capital, self.alpha) + (1.0 - self.depreciation) * capital) /
            ((1.0 + self.population_growth) * (1.0 + self.technology_growth));
    }
    pub fn simulate(self: Solow, initial: f64, periods: usize) f64 {
        var capital = initial;
        for (0..periods) |_| capital = self.step(capital);
        return capital;
    }
};

pub const Rbc = struct {
    beta: f64 = 0.96,
    alpha: f64 = 0.33,
    depreciation: f64 = 0.08,

    pub fn solve(self: Rbc, allocator: std.mem.Allocator, grid: []const f64, values: []f64, policy: []usize, tolerance: f64, max_iterations: usize) !f64 {
        if (grid.len == 0 or values.len != grid.len or policy.len != grid.len) return error.InvalidGrid;
        const next = try allocator.alloc(f64, grid.len);
        defer allocator.free(next);
        var residual: f64 = 0;
        for (0..max_iterations) |_| {
            residual = 0;
            for (grid, 0..) |capital, i| {
                var best = -std.math.inf(f64);
                var best_j: usize = 0;
                const resources = std.math.pow(f64, capital, self.alpha) + (1.0 - self.depreciation) * capital;
                for (grid, 0..) |next_capital, j| {
                    const consumption = resources - next_capital;
                    if (consumption <= 0) continue;
                    const candidate = @log(consumption) + self.beta * values[j];
                    if (candidate > best) {
                        best = candidate;
                        best_j = j;
                    }
                }
                next[i] = best;
                policy[i] = best_j;
                residual = @max(residual, @abs(best - values[i]));
            }
            @memcpy(values, next);
            if (residual <= tolerance) return residual;
        }
        return residual;
    }

    pub fn productivityPath(rho: f64, shock: f64, output: []f64) !void {
        if (@abs(rho) >= 1 or output.len == 0) return error.InvalidShock;
        output[0] = shock;
        for (output[1..], 1..) |*value, i| value.* = rho * output[i - 1];
    }
};

pub const SfcMatrix = struct {
    rows: usize,
    columns: usize,
    values: []const f64,

    pub fn validate(self: SfcMatrix, tolerance: f64) bool {
        if (self.values.len != self.rows * self.columns) return false;
        for (0..self.rows) |row| {
            var total: f64 = 0;
            for (0..self.columns) |column| total += self.values[row * self.columns + column];
            if (@abs(total) > tolerance) return false;
        }
        return true;
    }

    pub fn validateColumns(self: SfcMatrix, tolerance: f64) bool {
        if (self.values.len != self.rows * self.columns) return false;
        for (0..self.columns) |column| {
            var total: f64 = 0;
            for (0..self.rows) |row| total += self.values[row * self.columns + column];
            if (@abs(total) > tolerance) return false;
        }
        return true;
    }
};

pub const SectorBalanceSheet = struct {
    households: f64,
    firms: f64,
    banks: f64,
    government: f64,
    central_bank: f64,

    pub fn reconciles(self: SectorBalanceSheet, tolerance: f64) bool {
        return @abs(self.households + self.firms + self.banks + self.government + self.central_bank) <= tolerance;
    }
};

pub const SectorStocks = struct {
    values: [5]f64,
    pub fn applyFlows(self: *SectorStocks, flows: [5]f64, tolerance: f64) !void {
        var flow_total: f64 = 0;
        for (flows) |flow| flow_total += flow;
        if (@abs(flow_total) > tolerance) return error.UnbalancedFlows;
        for (&self.values, flows) |*stock, flow| stock.* += flow;
    }
    pub fn total(self: SectorStocks) f64 {
        var result: f64 = 0;
        for (self.values) |value| result += value;
        return result;
    }
};

pub const Household = struct { employed: bool, cash: i64, propensity: f64 };
pub const HeterogeneousEconomy = struct {
    seed: u64,
    households: []Household,
    firm_cash: i64,
    government_cash: i64,
    bank_cash: i64 = 0,
    firm_debt: i64 = 0,
    policy_rate: f64 = 0.02,
    price: i64 = 10,
    inventory: i64 = 1_000,

    pub fn step(self: *HeterogeneousEconomy, period: u64) void {
        var name_buffer: [32]u8 = undefined;
        const interest: i64 = @intFromFloat(@floor(@as(f64, @floatFromInt(self.firm_debt)) * self.policy_rate));
        const paid_interest = @min(@max(self.firm_cash, 0), interest);
        self.firm_cash -= paid_interest;
        self.bank_cash += paid_interest;
        for (self.households, 0..) |*household, i| {
            const name = std.fmt.bufPrint(&name_buffer, "labor/{d}/{d}", .{ period, i }) catch unreachable;
            var stream = core.Stream.init(self.seed, name);
            household.employed = stream.random().float(f64) > 0.05;
            const income: i64 = if (household.employed) 100 else 20;
            if (household.employed) {
                if (self.firm_cash < income) {
                    const credit = income - self.firm_cash;
                    self.bank_cash -= credit;
                    self.firm_cash += credit;
                    self.firm_debt += credit;
                }
                self.firm_cash -= income;
            } else self.government_cash -= income;
            const tax = @divTrunc(income, 10);
            const consumption: i64 = @intFromFloat(@floor(@as(f64, @floatFromInt(household.cash + income)) * household.propensity));
            household.cash += income - consumption - tax;
            self.government_cash += tax;
            self.firm_cash += consumption;
            self.inventory -= @min(self.inventory, @divTrunc(consumption, self.price));
        }
        self.inventory += @intCast(self.households.len * 8);
        const target = @as(i64, @intCast(self.households.len * 10));
        if (self.inventory < target) self.price += 1 else if (self.inventory > target * 2 and self.price > 1) self.price -= 1;
        const repayment = @min(@max(@divTrunc(self.firm_cash, 20), 0), self.firm_debt);
        self.firm_cash -= repayment;
        self.bank_cash += repayment;
        self.firm_debt -= repayment;
    }

    pub fn nominalStock(self: *const HeterogeneousEconomy) i64 {
        var total = self.firm_cash + self.government_cash + self.bank_cash;
        for (self.households) |household| total += household.cash;
        return total;
    }
};

pub fn taylorRate(neutral: f64, inflation: f64, target_inflation: f64, output_gap: f64) f64 {
    return @max(0.0, neutral + inflation + 1.5 * (inflation - target_inflation) + 0.5 * output_gap);
}

test "Solow simulation converges to analytical steady state" {
    const model = Solow{};
    const analytical = model.steadyState();
    const simulated = model.simulate(0.5, 2_000);
    try std.testing.expectApproxEqRel(analytical, simulated, 0.03);
}

test "RBC policy is monotone with a bounded Bellman residual" {
    const grid = [_]f64{ 0.2, 0.5, 1.0, 1.5, 2.0 };
    var values = [_]f64{0} ** grid.len;
    var policy = [_]usize{0} ** grid.len;
    const residual = try (Rbc{}).solve(std.testing.allocator, &grid, &values, &policy, 1e-7, 2_000);
    try std.testing.expect(residual <= 1e-6);
    for (policy[1..], policy[0 .. policy.len - 1]) |current, previous| try std.testing.expect(current >= previous);
    var impulse: [6]f64 = undefined;
    try Rbc.productivityPath(0.9, 0.01, &impulse);
    for (impulse[1..], impulse[0 .. impulse.len - 1]) |current, previous| try std.testing.expect(@abs(current) < @abs(previous));
}

test "stock-flow matrix rows reconcile" {
    const values = [_]f64{ -10, 8, 2, 5, -7, 2 };
    try std.testing.expect((SfcMatrix{ .rows = 2, .columns = 3, .values = &values }).validate(1e-12));
    try std.testing.expect((SectorBalanceSheet{ .households = 100, .firms = -40, .banks = 10, .government = -80, .central_bank = 10 }).reconciles(1e-12));
    const square = [_]f64{ 1, -1, -1, 1 };
    const complete = SfcMatrix{ .rows = 2, .columns = 2, .values = &square };
    try std.testing.expect(complete.validate(1e-12) and complete.validateColumns(1e-12));
    var stocks = SectorStocks{ .values = .{ 100, -40, 10, -80, 10 } };
    const before = stocks.total();
    try stocks.applyFlows(.{ 10, -4, 1, -8, 1 }, 1e-12);
    try std.testing.expectApproxEqAbs(before, stocks.total(), 1e-12);
}

test "heterogeneous economy is replayable" {
    var a_households = [_]Household{.{ .employed = true, .cash = 100, .propensity = 0.8 }};
    var b_households = a_households;
    var a = HeterogeneousEconomy{ .seed = 9, .households = &a_households, .firm_cash = 10_000, .government_cash = 10_000 };
    var b = HeterogeneousEconomy{ .seed = 9, .households = &b_households, .firm_cash = 10_000, .government_cash = 10_000 };
    const initial_stock = a.nominalStock();
    for (0..100) |period| {
        a.step(period);
        b.step(period);
    }
    try std.testing.expectEqual(a.households[0].cash, b.households[0].cash);
    try std.testing.expectEqual(a.households[0].employed, b.households[0].employed);
    try std.testing.expectEqual(initial_stock, a.nominalStock());
    try std.testing.expect(a.price > 0 and a.inventory >= 0);
}

test "policy rule respects the zero lower bound" {
    try std.testing.expectEqual(@as(f64, 0), taylorRate(-0.05, -0.02, 0.02, -0.1));
    try std.testing.expect(taylorRate(0.01, 0.04, 0.02, 0.01) > 0.04);
}

test "macro ABM survives one hundred seeded replications without nominal drift" {
    for (0..100) |seed| {
        var households = [_]Household{
            .{ .employed = true, .cash = 100, .propensity = 0.6 },
            .{ .employed = true, .cash = 150, .propensity = 0.8 },
            .{ .employed = false, .cash = 80, .propensity = 0.7 },
        };
        var economy = HeterogeneousEconomy{ .seed = seed, .households = &households, .firm_cash = 1_000_000, .government_cash = 1_000_000 };
        const stock = economy.nominalStock();
        for (0..100) |period| economy.step(period);
        try std.testing.expectEqual(stock, economy.nominalStock());
        try std.testing.expect(economy.price > 0 and economy.inventory >= 0);
    }
}
