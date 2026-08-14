//! Validated microeconomic preferences, equilibrium, games, and market mechanisms.

const std = @import("std");
const math = @import("math.zig");

pub const CobbDouglas = struct {
    alpha: f64,

    pub fn demand(self: CobbDouglas, income: f64, price_x: f64, price_y: f64) ![2]f64 {
        if (!(self.alpha > 0 and self.alpha < 1) or income < 0 or price_x <= 0 or price_y <= 0) return error.InvalidParameters;
        return .{ self.alpha * income / price_x, (1.0 - self.alpha) * income / price_y };
    }

    pub fn utility(self: CobbDouglas, x: f64, y: f64) !f64 {
        if (x < 0 or y < 0) return error.InvalidParameters;
        return std.math.pow(f64, x, self.alpha) * std.math.pow(f64, y, 1.0 - self.alpha);
    }
};

pub const Ces = struct {
    share: f64,
    rho: f64,
    pub fn utility(self: Ces, x: f64, y: f64) !f64 {
        if (!(self.share > 0 and self.share < 1) or self.rho == 0 or x < 0 or y < 0) return error.InvalidParameters;
        return std.math.pow(f64, self.share * std.math.pow(f64, x, self.rho) + (1 - self.share) * std.math.pow(f64, y, self.rho), 1.0 / self.rho);
    }
};

pub const CobbDouglasProduction = struct {
    productivity: f64 = 1,
    capital_share: f64 = 0.33,

    pub fn output(self: CobbDouglasProduction, capital: f64, labor: f64) !f64 {
        if (self.productivity <= 0 or !(self.capital_share > 0 and self.capital_share < 1) or capital < 0 or labor < 0) return error.InvalidParameters;
        return self.productivity * std.math.pow(f64, capital, self.capital_share) * std.math.pow(f64, labor, 1.0 - self.capital_share);
    }
};

pub const QuadraticCost = struct {
    fixed: f64 = 0,
    linear: f64,
    quadratic: f64 = 0,
    pub fn total(self: QuadraticCost, quantity: f64) !f64 {
        if (quantity < 0 or self.fixed < 0 or self.linear < 0 or self.quadratic < 0) return error.InvalidParameters;
        return self.fixed + self.linear * quantity + self.quadratic * quantity * quantity;
    }
    pub fn marginal(self: QuadraticCost, quantity: f64) !f64 {
        if (quantity < 0 or self.linear < 0 or self.quadratic < 0) return error.InvalidParameters;
        return self.linear + 2.0 * self.quadratic * quantity;
    }
};

pub const LinearMarket = struct {
    demand_intercept: f64,
    demand_slope: f64,
    supply_intercept: f64,
    supply_slope: f64,

    pub fn excess(self: LinearMarket, price: f64) f64 {
        return (self.demand_intercept - self.demand_slope * price) - (self.supply_intercept + self.supply_slope * price);
    }
    pub fn equilibrium(self: LinearMarket) !f64 {
        const Context = struct {
            market: LinearMarket,
            fn call(ctx: @This(), price: f64) f64 {
                return ctx.market.excess(price);
            }
        };
        return math.bisect(Context{ .market = self }, Context.call, 0, 1_000_000, 1e-10, 200);
    }
};

pub const Cournot = struct {
    firms: u32,
    demand_intercept: f64,
    marginal_cost: f64,
    slope: f64,
    pub fn symmetricQuantity(self: Cournot) !f64 {
        if (self.firms == 0 or self.slope <= 0 or self.demand_intercept < self.marginal_cost) return error.InvalidParameters;
        return (self.demand_intercept - self.marginal_cost) / (self.slope * @as(f64, @floatFromInt(self.firms + 1)));
    }
};

pub const Bertrand = struct {
    marginal_cost: f64,
    pub fn symmetricPrice(self: Bertrand) f64 {
        return self.marginal_cost;
    }
};

pub const TwoByTwoGame = struct {
    payoffs: [2][2][2]f64,
    pub fn pureNash(self: TwoByTwoGame, output: *[4][2]u8) usize {
        var count: usize = 0;
        for (0..2) |row| for (0..2) |column| {
            const p1_best = self.payoffs[row][column][0] >= self.payoffs[1 - row][column][0];
            const p2_best = self.payoffs[row][column][1] >= self.payoffs[row][1 - column][1];
            if (p1_best and p2_best) {
                output[count] = .{ @intCast(row), @intCast(column) };
                count += 1;
            }
        };
        return count;
    }
};

pub fn replicatorStep(shares: []f64, fitness: []const f64, dt: f64) !void {
    if (shares.len != fitness.len or shares.len == 0 or dt < 0) return error.InvalidParameters;
    var average: f64 = 0;
    for (shares, fitness) |share, value| average += share * value;
    var total: f64 = 0;
    for (shares, fitness) |*share, value| {
        share.* *= 1.0 + dt * (value - average);
        total += share.*;
    }
    if (total <= 0) return error.InvalidParameters;
    for (shares) |*share| share.* /= total;
}

pub const WalrasAgent = struct { alpha: f64, endowment: [2]f64 };

pub fn walrasExcessX(agents: []const WalrasAgent, price_x: f64) !f64 {
    if (price_x <= 0) return error.InvalidParameters;
    var excess: f64 = 0;
    for (agents) |agent| {
        const income = price_x * agent.endowment[0] + agent.endowment[1];
        const demand_x = agent.alpha * income / price_x;
        excess += demand_x - agent.endowment[0];
    }
    return excess;
}

pub fn walrasPrice(agents: []const WalrasAgent) !f64 {
    const Context = struct {
        agents: []const WalrasAgent,
        fn call(ctx: @This(), price: f64) f64 {
            return walrasExcessX(ctx.agents, price) catch std.math.nan(f64);
        }
    };
    return math.bisect(Context{ .agents = agents }, Context.call, 1e-6, 1e6, 1e-10, 300);
}

pub const TradingPostOrder = struct { agent: u64, bid_money: f64, offer_goods: f64 };
pub const TradingPostAllocation = struct { agent: u64, money_received: f64, goods_received: f64 };

pub fn clearTradingPost(orders: []const TradingPostOrder, output: []TradingPostAllocation) !f64 {
    if (orders.len == 0 or output.len < orders.len) return error.InvalidParameters;
    var total_bid: f64 = 0;
    var total_offer: f64 = 0;
    for (orders) |order| {
        if (order.bid_money < 0 or order.offer_goods < 0) return error.InvalidParameters;
        total_bid += order.bid_money;
        total_offer += order.offer_goods;
    }
    if (total_bid <= 0 or total_offer <= 0) return error.InvalidParameters;
    const price = total_bid / total_offer;
    for (orders, 0..) |order, i| output[i] = .{
        .agent = order.agent,
        .money_received = order.offer_goods * price,
        .goods_received = order.bid_money / price,
    };
    return price;
}

pub const BilateralTrade = struct { buyer: u64, seller: u64, price: f64, quantity: f64 };
pub fn bilateralExchange(buyer: u64, seller: u64, bid: f64, ask: f64, quantity: f64) !?BilateralTrade {
    if (bid < 0 or ask < 0 or quantity <= 0) return error.InvalidParameters;
    if (bid < ask) return null;
    return .{ .buyer = buyer, .seller = seller, .price = (bid + ask) / 2.0, .quantity = quantity };
}

test "Cobb-Douglas demand exhausts the budget" {
    const pref = CobbDouglas{ .alpha = 0.4 };
    const demand = try pref.demand(100, 2, 4);
    try std.testing.expectApproxEqAbs(100.0, demand[0] * 2 + demand[1] * 4, 1e-10);
}

test "CES utility and normal-form games satisfy reference fixtures" {
    const utility = try (Ces{ .share = 0.5, .rho = 0.5 }).utility(4, 4);
    try std.testing.expectApproxEqAbs(4.0, utility, 1e-12);
    const prisoners = TwoByTwoGame{ .payoffs = .{
        .{ .{ 3, 3 }, .{ 0, 5 } },
        .{ .{ 5, 0 }, .{ 1, 1 } },
    } };
    var equilibria: [4][2]u8 = undefined;
    const count = prisoners.pureNash(&equilibria);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualDeep([2]u8{ 1, 1 }, equilibria[0]);
    try std.testing.expectEqual(@as(f64, 10), (Bertrand{ .marginal_cost = 10 }).symmetricPrice());
}

test "linear market and Cournot match closed-form equilibria" {
    const market = LinearMarket{ .demand_intercept = 100, .demand_slope = 1, .supply_intercept = 20, .supply_slope = 1 };
    try std.testing.expectApproxEqAbs(40.0, try market.equilibrium(), 1e-8);
    try std.testing.expectApproxEqAbs(30.0, try (Cournot{ .firms = 2, .demand_intercept = 100, .marginal_cost = 10, .slope = 1 }).symmetricQuantity(), 1e-12);
}

test "two-agent Walrasian exchange clears and obeys Walras law" {
    const agents = [_]WalrasAgent{
        .{ .alpha = 0.75, .endowment = .{ 1, 4 } },
        .{ .alpha = 0.25, .endowment = .{ 4, 1 } },
    };
    const price = try walrasPrice(&agents);
    try std.testing.expectApproxEqAbs(0.0, try walrasExcessX(&agents, price), 1e-8);
}

test "replicator dynamics preserve the simplex" {
    var shares = [_]f64{ 0.5, 0.5 };
    try replicatorStep(&shares, &.{ 2, 1 }, 0.1);
    try std.testing.expectApproxEqAbs(1.0, shares[0] + shares[1], 1e-12);
    try std.testing.expect(shares[0] > shares[1]);
}

test "production, costs, and bilateral exchange respect domains" {
    try std.testing.expectApproxEqAbs(4.0, try (CobbDouglasProduction{ .capital_share = 0.5 }).output(4, 4), 1e-12);
    try std.testing.expectApproxEqAbs(7.0, try (QuadraticCost{ .linear = 1, .quadratic = 0.5 }).marginal(6), 1e-12);
    try std.testing.expect((try bilateralExchange(1, 2, 10, 8, 3)) != null);
    try std.testing.expect((try bilateralExchange(1, 2, 7, 8, 3)) == null);
}

test "trading post conserves submitted money and goods" {
    const orders = [_]TradingPostOrder{
        .{ .agent = 1, .bid_money = 80, .offer_goods = 2 },
        .{ .agent = 2, .bid_money = 20, .offer_goods = 8 },
    };
    var allocations: [2]TradingPostAllocation = undefined;
    _ = try clearTradingPost(&orders, &allocations);
    var money: f64 = 0;
    var goods: f64 = 0;
    for (allocations) |allocation| {
        money += allocation.money_received;
        goods += allocation.goods_received;
    }
    try std.testing.expectApproxEqAbs(100.0, money, 1e-12);
    try std.testing.expectApproxEqAbs(10.0, goods, 1e-12);
}
