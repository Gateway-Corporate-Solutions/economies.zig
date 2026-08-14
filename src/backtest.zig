//! Point-in-time market data, broker execution, portfolio accounting, and evaluation.

const std = @import("std");
const accounting = @import("accounting.zig");

pub const Timestamp = i64;
pub const MarketEvent = union(enum) {
    bar: Bar,
    quote: Quote,
    trade: TradePrint,
    dividend: Dividend,
    split: Split,
    rate: Rate,
    symbol_metadata: SymbolMetadata,
};
pub const Bar = struct { timestamp: Timestamp, symbol: u32, open: i64, high: i64, low: i64, close: i64 };
pub const Quote = struct { timestamp: Timestamp, symbol: u32, bid: i64, ask: i64 };
pub const TradePrint = struct { timestamp: Timestamp, symbol: u32, price: i64, quantity: u64 };
pub const Dividend = struct { timestamp: Timestamp, symbol: u32, minor_per_share: i64 };
pub const Split = struct { timestamp: Timestamp, symbol: u32, numerator: u32, denominator: u32 };
pub const Rate = struct { timestamp: Timestamp, annual_rate: f64 };
pub const SymbolMetadata = struct { timestamp: Timestamp, symbol: u32, active: bool };

pub fn eventTimestamp(event: MarketEvent) Timestamp {
    return switch (event) {
        inline else => |value| value.timestamp,
    };
}

pub const PointInTimeFeed = struct {
    events: []const MarketEvent,
    cursor: usize = 0,
    now: Timestamp = std.math.minInt(Timestamp),

    pub fn next(self: *PointInTimeFeed) !?MarketEvent {
        if (self.cursor >= self.events.len) return null;
        const event = self.events[self.cursor];
        const timestamp = eventTimestamp(event);
        if (timestamp < self.now) return error.NonMonotonicData;
        self.cursor += 1;
        self.now = timestamp;
        return event;
    }

    pub fn eventAt(self: *const PointInTimeFeed, index: usize) !MarketEvent {
        if (index >= self.cursor) return error.FutureData;
        return self.events[index];
    }
};

pub const Session = struct { open: Timestamp, close: Timestamp };
pub const ExchangeCalendar = struct {
    sessions: []const Session,
    pub fn isOpen(self: ExchangeCalendar, timestamp: Timestamp) bool {
        for (self.sessions) |session| if (timestamp >= session.open and timestamp <= session.close) return true;
        return false;
    }
};

pub const OrderSide = enum { buy, sell };
pub const OrderIntent = struct { symbol: u32, side: OrderSide, quantity: i64, limit: ?i64 = null };
pub const Fill = struct { symbol: u32, side: OrderSide, quantity: i64, price: i64, fee: i64, timestamp: Timestamp };

pub const Holding = struct { symbol: u32, quantity: i64, average_price: i64 = 0 };
pub const AccountView = struct { cash: i64, holdings: []const Holding };
pub const MarketView = struct { bar: Bar, account: AccountView };

/// Invokes a strategy with immutable market/account state. Intents are returned in caller-owned storage.
pub fn strategyIntents(strategy: anytype, view: MarketView, output: []OrderIntent) !usize {
    const count = try strategy.onBar(view, output);
    if (count > output.len) return error.TooManyIntents;
    return count;
}

pub const BuyAndHoldStrategy = struct {
    quantity: i64,
    pub fn onBar(self: *BuyAndHoldStrategy, view: MarketView, output: []OrderIntent) !usize {
        const held = for (view.account.holdings) |holding| {
            if (holding.symbol == view.bar.symbol) break holding.quantity;
        } else 0;
        if (held > 0 or self.quantity <= 0 or output.len == 0) return 0;
        output[0] = .{ .symbol = view.bar.symbol, .side = .buy, .quantity = self.quantity };
        return 1;
    }
};

pub const MovingAverageStrategy = struct {
    short_window: usize,
    long_window: usize,
    quantity: i64,
    closes: [256]i64 = [_]i64{0} ** 256,
    count: usize = 0,

    pub fn onBar(self: *MovingAverageStrategy, view: MarketView, output: []OrderIntent) !usize {
        if (self.long_window > self.closes.len or self.long_window <= self.short_window or self.short_window == 0) return error.InvalidWindow;
        if (self.count < self.closes.len) {
            self.closes[self.count] = view.bar.close;
            self.count += 1;
        } else {
            std.mem.copyForwards(i64, self.closes[0 .. self.closes.len - 1], self.closes[1..]);
            self.closes[self.closes.len - 1] = view.bar.close;
        }
        if (self.count < self.long_window or output.len == 0) return 0;
        const signal = try movingAverageSignal(self.closes[self.count - self.long_window .. self.count], self.short_window, self.long_window);
        const held = for (view.account.holdings) |holding| {
            if (holding.symbol == view.bar.symbol) break holding.quantity;
        } else 0;
        if (signal == .buy and held == 0) {
            output[0] = .{ .symbol = view.bar.symbol, .side = .buy, .quantity = self.quantity };
            return 1;
        }
        if (signal == .sell and held > 0) {
            if (held > 0) {
                output[0] = .{ .symbol = view.bar.symbol, .side = .sell, .quantity = held };
                return 1;
            }
        }
        return 0;
    }
};

pub const Portfolio = struct {
    allocator: std.mem.Allocator,
    cash: i64,
    holdings: std.ArrayList(Holding) = .empty,
    fees_paid: i64 = 0,
    realized_pnl: i64 = 0,
    journal: accounting.Journal,

    const issuer_account: accounting.AccountId = 0;
    const cash_account: accounting.AccountId = 1;
    const market_account: accounting.AccountId = 2;
    const fee_account: accounting.AccountId = 3;

    pub fn init(allocator: std.mem.Allocator, cash: i64) !Portfolio {
        if (cash < 0) return error.InvalidCash;
        var portfolio = Portfolio{ .allocator = allocator, .cash = cash, .journal = accounting.Journal.init(allocator) };
        errdefer portfolio.journal.deinit();
        if (cash > 0) try portfolio.journal.post(&.{
            .{ .account = issuer_account, .amount = .{ .currency = .USD, .minor = -cash } },
            .{ .account = cash_account, .amount = .{ .currency = .USD, .minor = cash } },
        });
        return portfolio;
    }
    pub fn deinit(self: *Portfolio) void {
        self.holdings.deinit(self.allocator);
        self.journal.deinit();
    }
    pub fn quantity(self: *const Portfolio, symbol: u32) i64 {
        for (self.holdings.items) |holding| if (holding.symbol == symbol) return holding.quantity;
        return 0;
    }
    fn getOrCreate(self: *Portfolio, symbol: u32) !*Holding {
        for (self.holdings.items) |*holding| if (holding.symbol == symbol) return holding;
        try self.holdings.append(self.allocator, .{ .symbol = symbol, .quantity = 0 });
        return &self.holdings.items[self.holdings.items.len - 1];
    }
    pub fn applyFill(self: *Portfolio, fill: Fill) !void {
        if (fill.quantity <= 0 or fill.price <= 0 or fill.fee < 0) return error.InvalidFill;
        const holding = try self.getOrCreate(fill.symbol);
        const notional = std.math.mul(i64, fill.quantity, fill.price) catch return error.Overflow;
        if (fill.side == .buy) {
            const cost = std.math.add(i64, notional, fill.fee) catch return error.Overflow;
            if (cost > self.cash) return error.InsufficientCash;
            const old_cost = std.math.mul(i64, holding.quantity, holding.average_price) catch return error.Overflow;
            try self.journal.post(&.{
                .{ .account = cash_account, .amount = .{ .currency = .USD, .minor = -cost } },
                .{ .account = market_account, .amount = .{ .currency = .USD, .minor = notional } },
                .{ .account = fee_account, .amount = .{ .currency = .USD, .minor = fill.fee } },
            });
            holding.quantity += fill.quantity;
            holding.average_price = @divTrunc(old_cost + notional, holding.quantity);
            self.cash -= cost;
        } else {
            if (fill.quantity > holding.quantity) return error.InsufficientPosition;
            try self.journal.post(&.{
                .{ .account = cash_account, .amount = .{ .currency = .USD, .minor = notional - fill.fee } },
                .{ .account = market_account, .amount = .{ .currency = .USD, .minor = -notional } },
                .{ .account = fee_account, .amount = .{ .currency = .USD, .minor = fill.fee } },
            });
            self.cash += notional - fill.fee;
            self.realized_pnl += (fill.price - holding.average_price) * fill.quantity - fill.fee;
            holding.quantity -= fill.quantity;
        }
        self.fees_paid += fill.fee;
    }
    pub fn applyDividend(self: *Portfolio, dividend: Dividend) !void {
        const amount = std.math.mul(i64, self.quantity(dividend.symbol), dividend.minor_per_share) catch return error.Overflow;
        if (amount < 0) return error.InvalidDividend;
        if (amount > 0) try self.journal.post(&.{
            .{ .account = issuer_account, .amount = .{ .currency = .USD, .minor = -amount } },
            .{ .account = cash_account, .amount = .{ .currency = .USD, .minor = amount } },
        });
        self.cash += amount;
    }
    pub fn applySplit(self: *Portfolio, split: Split) !void {
        if (split.numerator == 0 or split.denominator == 0) return error.InvalidSplit;
        const holding = try self.getOrCreate(split.symbol);
        const scaled = std.math.mul(i64, holding.quantity, split.numerator) catch return error.Overflow;
        if (@rem(scaled, split.denominator) != 0) return error.FractionalShare;
        holding.quantity = @divTrunc(scaled, split.denominator);
        holding.average_price = @divTrunc(holding.average_price * split.denominator, split.numerator);
    }
    pub fn equity(self: *const Portfolio, symbol: u32, price: i64) i64 {
        return self.cash + self.quantity(symbol) * price;
    }
    pub fn unrealizedPnl(self: *const Portfolio, symbol: u32, price: i64) i64 {
        for (self.holdings.items) |holding| if (holding.symbol == symbol) return (price - holding.average_price) * holding.quantity;
        return 0;
    }
    pub fn applyFinancing(self: *Portfolio, minor: i64) !void {
        if (minor != 0) try self.journal.post(&.{
            .{ .account = issuer_account, .amount = .{ .currency = .USD, .minor = -minor } },
            .{ .account = cash_account, .amount = .{ .currency = .USD, .minor = minor } },
        });
        self.cash = std.math.add(i64, self.cash, minor) catch return error.Overflow;
    }

    pub fn reconciles(self: *const Portfolio) bool {
        const ledger_cash = self.journal.balance(cash_account, .USD) catch return false;
        return ledger_cash.minor == self.cash;
    }
};

pub const Broker = struct {
    fee_per_order: i64 = 0,
    slippage_ticks: i64 = 0,
    latency: Timestamp = 0,

    pub fn fillBar(self: Broker, intent: OrderIntent, bar: Bar) !?Fill {
        if (intent.symbol != bar.symbol or intent.quantity <= 0) return null;
        var price = bar.open;
        if (intent.limit) |limit| {
            if (intent.side == .buy) {
                if (bar.low > limit) return null;
                price = @min(bar.open, limit);
            } else {
                if (bar.high < limit) return null;
                price = @max(bar.open, limit);
            }
        }
        price += if (intent.side == .buy) self.slippage_ticks else -self.slippage_ticks;
        if (price <= 0) return error.InvalidFill;
        return .{ .symbol = intent.symbol, .side = intent.side, .quantity = intent.quantity, .price = price, .fee = self.fee_per_order, .timestamp = bar.timestamp };
    }

    pub fn fillQuote(self: Broker, intent: OrderIntent, submitted_at: Timestamp, quote: Quote) !?Fill {
        if (quote.timestamp < submitted_at + self.latency or quote.symbol != intent.symbol or intent.quantity <= 0) return null;
        var price = if (intent.side == .buy) quote.ask else quote.bid;
        if (intent.limit) |limit| {
            if ((intent.side == .buy and price > limit) or (intent.side == .sell and price < limit)) return null;
        }
        price += if (intent.side == .buy) self.slippage_ticks else -self.slippage_ticks;
        if (price <= 0 or quote.bid > quote.ask) return error.InvalidQuote;
        return .{ .symbol = intent.symbol, .side = intent.side, .quantity = intent.quantity, .price = price, .fee = self.fee_per_order, .timestamp = quote.timestamp };
    }
};

pub const PendingSettlement = struct { due: Timestamp, cash_delta: i64 };
pub fn settleDue(cash: *i64, pending: []PendingSettlement, now: Timestamp) usize {
    var settled: usize = 0;
    for (pending) |*item| if (item.due <= now and item.cash_delta != 0) {
        cash.* += item.cash_delta;
        item.cash_delta = 0;
        settled += 1;
    };
    return settled;
}

pub const RunReport = struct { events: usize, fills: usize, final_equity: i64 };

pub fn run(strategy: anytype, feed: *PointInTimeFeed, portfolio: *Portfolio, broker: Broker, equity_curve: []i64) !RunReport {
    var event_count: usize = 0;
    var fill_count: usize = 0;
    var equity_count: usize = 0;
    var last_equity = portfolio.cash;
    while (try feed.next()) |event| {
        event_count += 1;
        switch (event) {
            .bar => |bar| {
                var intents: [16]OrderIntent = undefined;
                const count = try strategyIntents(strategy, .{ .bar = bar, .account = .{ .cash = portfolio.cash, .holdings = portfolio.holdings.items } }, &intents);
                for (intents[0..count]) |intent| if (try broker.fillBar(intent, bar)) |fill| {
                    try portfolio.applyFill(fill);
                    fill_count += 1;
                };
                last_equity = portfolio.equity(bar.symbol, bar.close);
                if (equity_count >= equity_curve.len) return error.OutputTooSmall;
                equity_curve[equity_count] = last_equity;
                equity_count += 1;
            },
            .dividend => |dividend| try portfolio.applyDividend(dividend),
            .split => |split| try portfolio.applySplit(split),
            .rate => |rate| {
                if (portfolio.cash < 0) {
                    const financing: i64 = @intFromFloat(@round(@as(f64, @floatFromInt(portfolio.cash)) * rate.annual_rate));
                    try portfolio.applyFinancing(financing);
                }
            },
            else => {},
        }
    }
    return .{ .events = event_count, .fills = fill_count, .final_equity = last_equity };
}

pub const Metrics = struct {
    total_return: f64,
    max_drawdown: f64,
    volatility: f64,
    sharpe: f64,
    sortino: f64,

    pub fn compute(equity_curve: []const f64) !Metrics {
        if (equity_curve.len < 2 or equity_curve[0] <= 0) return error.InsufficientData;
        var peak = equity_curve[0];
        var max_drawdown: f64 = 0;
        var mean: f64 = 0;
        var m2: f64 = 0;
        var downside_squared: f64 = 0;
        var count: usize = 0;
        for (equity_curve[1..], equity_curve[0 .. equity_curve.len - 1]) |equity, prior| {
            peak = @max(peak, equity);
            max_drawdown = @max(max_drawdown, (peak - equity) / peak);
            const value = equity / prior - 1.0;
            count += 1;
            const delta = value - mean;
            mean += delta / @as(f64, @floatFromInt(count));
            m2 += delta * (value - mean);
            if (value < 0) downside_squared += value * value;
        }
        const volatility = if (count > 1) @sqrt(m2 / @as(f64, @floatFromInt(count - 1))) else 0;
        const downside = @sqrt(downside_squared / @as(f64, @floatFromInt(count)));
        return .{ .total_return = equity_curve[equity_curve.len - 1] / equity_curve[0] - 1.0, .max_drawdown = max_drawdown, .volatility = volatility, .sharpe = if (volatility == 0) 0 else mean / volatility, .sortino = if (downside == 0) 0 else mean / downside };
    }
};

pub const TradeMetrics = struct { turnover: i64, hit_rate: f64, profit_factor: f64 };
pub fn evaluateTrades(realized_pnl: []const i64, notionals: []const i64) !TradeMetrics {
    if (realized_pnl.len == 0 or realized_pnl.len != notionals.len) return error.InsufficientData;
    var wins: usize = 0;
    var gross_profit: i128 = 0;
    var gross_loss: i128 = 0;
    var turnover: i64 = 0;
    for (realized_pnl, notionals) |pnl, notional| {
        if (notional < 0) return error.InvalidNotional;
        turnover = std.math.add(i64, turnover, notional) catch return error.Overflow;
        if (pnl > 0) {
            wins += 1;
            gross_profit += pnl;
        } else if (pnl < 0) gross_loss += -@as(i128, pnl);
    }
    return .{
        .turnover = turnover,
        .hit_rate = @as(f64, @floatFromInt(wins)) / @as(f64, @floatFromInt(realized_pnl.len)),
        .profit_factor = if (gross_loss == 0) std.math.inf(f64) else @as(f64, @floatFromInt(gross_profit)) / @as(f64, @floatFromInt(gross_loss)),
    };
}

pub fn movingAverageSignal(closes: []const i64, short_window: usize, long_window: usize) !OrderSide {
    if (short_window == 0 or long_window <= short_window or closes.len < long_window) return error.InsufficientData;
    var short_total: i128 = 0;
    var long_total: i128 = 0;
    for (closes[closes.len - short_window ..]) |value| short_total += value;
    for (closes[closes.len - long_window ..]) |value| long_total += value;
    return if (short_total * @as(i128, @intCast(long_window)) > long_total * @as(i128, @intCast(short_window))) .buy else .sell;
}

pub fn crossSectionalWinner(returns: []const f64) !usize {
    if (returns.len == 0) return error.InsufficientData;
    var best: usize = 0;
    for (returns[1..], 1..) |value, i| if (value > returns[best]) {
        best = i;
    };
    return best;
}

pub const MakerQuotes = struct { bid: f64, ask: f64 };
pub fn avellanedaStoikovQuotes(mid: f64, inventory: f64, risk_aversion: f64, variance: f64, horizon: f64, liquidity: f64) !MakerQuotes {
    if (mid <= 0 or risk_aversion <= 0 or variance < 0 or horizon < 0 or liquidity <= 0) return error.InvalidParameters;
    const reservation = mid - inventory * risk_aversion * variance * horizon;
    const spread = risk_aversion * variance * horizon + 2.0 / risk_aversion * @log(1.0 + risk_aversion / liquidity);
    return .{ .bid = reservation - spread / 2.0, .ask = reservation + spread / 2.0 };
}

pub const Partition = struct { train_start: usize, train_end: usize, test_start: usize, test_end: usize };
pub fn rollingPartitions(total: usize, train: usize, test_size: usize, step: usize, output: []Partition) !usize {
    if (train == 0 or test_size == 0 or step == 0 or train + test_size > total) return error.InvalidPartition;
    var count: usize = 0;
    var start: usize = 0;
    while (start + train + test_size <= total and count < output.len) : (start += step) {
        output[count] = .{ .train_start = start, .train_end = start + train, .test_start = start + train, .test_end = start + train + test_size };
        count += 1;
    }
    return count;
}

test "point-in-time feed rejects future access and backward time" {
    const events = [_]MarketEvent{
        .{ .bar = .{ .timestamp = 1, .symbol = 1, .open = 100, .high = 110, .low = 90, .close = 105 } },
        .{ .bar = .{ .timestamp = 2, .symbol = 1, .open = 105, .high = 115, .low = 100, .close = 110 } },
    };
    var feed = PointInTimeFeed{ .events = &events };
    try std.testing.expectError(error.FutureData, feed.eventAt(0));
    _ = (try feed.next()).?;
    _ = try feed.eventAt(0);
    try std.testing.expectError(error.FutureData, feed.eventAt(1));
}

test "feed rejects nonmonotonic source data" {
    const events = [_]MarketEvent{
        .{ .trade = .{ .timestamp = 2, .symbol = 1, .price = 100, .quantity = 1 } },
        .{ .trade = .{ .timestamp = 1, .symbol = 1, .price = 100, .quantity = 1 } },
    };
    var feed = PointInTimeFeed{ .events = &events };
    _ = try feed.next();
    try std.testing.expectError(error.NonMonotonicData, feed.next());
}

test "buy and hold reconciles fees, dividend, split, and sale" {
    var portfolio = try Portfolio.init(std.testing.allocator, 10_000);
    defer portfolio.deinit();
    try portfolio.applyFill(.{ .symbol = 1, .side = .buy, .quantity = 10, .price = 100, .fee = 5, .timestamp = 1 });
    try portfolio.applyDividend(.{ .timestamp = 2, .symbol = 1, .minor_per_share = 2 });
    try portfolio.applySplit(.{ .timestamp = 3, .symbol = 1, .numerator = 2, .denominator = 1 });
    try portfolio.applyFill(.{ .symbol = 1, .side = .sell, .quantity = 20, .price = 60, .fee = 5, .timestamp = 4 });
    try std.testing.expectEqual(@as(i64, 10_210), portfolio.cash);
    try std.testing.expectEqual(@as(i64, 0), portfolio.quantity(1));
    try std.testing.expectEqual(@as(i64, 10), portfolio.fees_paid);
    try std.testing.expect(portfolio.reconciles());
}

test "nonnegative costs cannot improve a fixed execution path" {
    const bar = Bar{ .timestamp = 1, .symbol = 1, .open = 100, .high = 110, .low = 90, .close = 105 };
    const intent = OrderIntent{ .symbol = 1, .side = .buy, .quantity = 10 };
    const free = (try (Broker{}).fillBar(intent, bar)).?;
    const costly = (try (Broker{ .fee_per_order = 5, .slippage_ticks = 2 }).fillBar(intent, bar)).?;
    try std.testing.expect(costly.price * costly.quantity + costly.fee >= free.price * free.quantity + free.fee);
}

test "quote execution respects latency, spread, and exchange calendar" {
    const calendar = ExchangeCalendar{ .sessions = &.{.{ .open = 10, .close = 20 }} };
    try std.testing.expect(calendar.isOpen(15));
    try std.testing.expect(!calendar.isOpen(21));
    const broker = Broker{ .latency = 2 };
    const intent = OrderIntent{ .symbol = 1, .side = .buy, .quantity = 1 };
    try std.testing.expect((try broker.fillQuote(intent, 10, .{ .timestamp = 11, .symbol = 1, .bid = 99, .ask = 101 })) == null);
    const fill = (try broker.fillQuote(intent, 10, .{ .timestamp = 12, .symbol = 1, .bid = 99, .ask = 101 })).?;
    try std.testing.expectEqual(@as(i64, 101), fill.price);
}

test "settlement and walk-forward partitions are explicit" {
    var cash: i64 = 100;
    var pending = [_]PendingSettlement{ .{ .due = 2, .cash_delta = 50 }, .{ .due = 3, .cash_delta = -10 } };
    try std.testing.expectEqual(@as(usize, 1), settleDue(&cash, &pending, 2));
    try std.testing.expectEqual(@as(i64, 150), cash);
    var partitions: [8]Partition = undefined;
    const count = try rollingPartitions(20, 10, 5, 5, &partitions);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expect(partitions[0].train_end <= partitions[0].test_start);
    try std.testing.expectEqual(@as(usize, 1), try crossSectionalWinner(&.{ 0.1, 0.2, -0.1 }));
}

test "performance and market-making metrics are internally consistent" {
    const trade_metrics = try evaluateTrades(&.{ 10, -5, 0, 20 }, &.{ 100, 100, 50, 200 });
    try std.testing.expectEqual(@as(i64, 450), trade_metrics.turnover);
    try std.testing.expectApproxEqAbs(0.5, trade_metrics.hit_rate, 1e-12);
    try std.testing.expectApproxEqAbs(6.0, trade_metrics.profit_factor, 1e-12);
    const quotes = try avellanedaStoikovQuotes(100, 0, 0.1, 0.04, 1, 1.5);
    try std.testing.expect(quotes.bid < 100 and quotes.ask > 100 and quotes.bid < quotes.ask);
}

test "bar limits do not fill outside the observed range" {
    const bar = Bar{ .timestamp = 1, .symbol = 1, .open = 100, .high = 105, .low = 95, .close = 101 };
    const broker = Broker{};
    try std.testing.expect((try broker.fillBar(.{ .symbol = 1, .side = .buy, .quantity = 1, .limit = 94 }, bar)) == null);
    try std.testing.expect((try broker.fillBar(.{ .symbol = 1, .side = .sell, .quantity = 1, .limit = 106 }, bar)) == null);
}

test "strategy boundary returns values and cannot mutate portfolio state" {
    const Strategy = struct {
        fn onBar(_: @This(), view: MarketView, output: []OrderIntent) !usize {
            if (view.bar.close > view.bar.open and view.account.cash > 0) {
                output[0] = .{ .symbol = view.bar.symbol, .side = .buy, .quantity = 1 };
                return 1;
            }
            return 0;
        }
    };
    var intents: [2]OrderIntent = undefined;
    const count = try strategyIntents(Strategy{}, .{
        .bar = .{ .timestamp = 1, .symbol = 7, .open = 100, .high = 110, .low = 90, .close = 105 },
        .account = .{ .cash = 1_000, .holdings = &.{} },
    }, &intents);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u32, 7), intents[0].symbol);
}

test "reference strategy state follows confirmed holdings rather than emitted intents" {
    var strategy = BuyAndHoldStrategy{ .quantity = 2 };
    var intents: [1]OrderIntent = undefined;
    const empty_view = MarketView{
        .bar = .{ .timestamp = 1, .symbol = 1, .open = 100, .high = 100, .low = 100, .close = 100 },
        .account = .{ .cash = 1_000, .holdings = &.{} },
    };
    try std.testing.expectEqual(@as(usize, 1), try strategyIntents(&strategy, empty_view, &intents));
    try std.testing.expectEqual(@as(usize, 1), try strategyIntents(&strategy, empty_view, &intents));
    const holdings = [_]Holding{.{ .symbol = 1, .quantity = 2 }};
    try std.testing.expectEqual(@as(usize, 0), try strategyIntents(&strategy, .{ .bar = empty_view.bar, .account = .{ .cash = 800, .holdings = &holdings } }, &intents));
}

test "end-to-end buy and hold uses point-in-time events, broker, and shared ledger" {
    const events = [_]MarketEvent{
        .{ .bar = .{ .timestamp = 1, .symbol = 1, .open = 100, .high = 105, .low = 95, .close = 102 } },
        .{ .dividend = .{ .timestamp = 2, .symbol = 1, .minor_per_share = 2 } },
        .{ .bar = .{ .timestamp = 3, .symbol = 1, .open = 105, .high = 112, .low = 101, .close = 110 } },
    };
    var feed = PointInTimeFeed{ .events = &events };
    var portfolio = try Portfolio.init(std.testing.allocator, 10_000);
    defer portfolio.deinit();
    var strategy = BuyAndHoldStrategy{ .quantity = 10 };
    var equity: [2]i64 = undefined;
    const report = try run(&strategy, &feed, &portfolio, .{ .fee_per_order = 5 }, &equity);
    try std.testing.expectEqual(@as(usize, 3), report.events);
    try std.testing.expectEqual(@as(usize, 1), report.fills);
    try std.testing.expectEqual(@as(i64, 10_115), report.final_equity);
    try std.testing.expect(portfolio.reconciles());
}
