//! Auctions, clearing, settlement primitives, and a deterministic reference limit order book.

const std = @import("std");

pub const Side = enum { buy, sell };
pub const TimeInForce = enum { gtc, ioc };
pub const Order = struct {
    id: u64,
    owner: u64,
    side: Side,
    price_ticks: i64,
    quantity: u64,
    sequence: u64 = 0,
    tif: TimeInForce = .gtc,
};
pub const Trade = struct { buy_order: u64, sell_order: u64, price_ticks: i64, quantity: u64 };

pub const OrderBook = struct {
    allocator: std.mem.Allocator,
    bids: std.ArrayList(Order) = .empty,
    asks: std.ArrayList(Order) = .empty,
    trades: std.ArrayList(Trade) = .empty,
    next_sequence: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) OrderBook {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *OrderBook) void {
        self.bids.deinit(self.allocator);
        self.asks.deinit(self.allocator);
        self.trades.deinit(self.allocator);
    }

    fn better(side: Side, a: Order, b: Order) bool {
        if (a.price_ticks != b.price_ticks) return if (side == .buy) a.price_ticks > b.price_ticks else a.price_ticks < b.price_ticks;
        return a.sequence < b.sequence;
    }

    fn bestIndex(orders: []const Order, side: Side) ?usize {
        if (orders.len == 0) return null;
        var best: usize = 0;
        for (orders[1..], 1..) |order, i| if (better(side, order, orders[best])) {
            best = i;
        };
        return best;
    }

    pub fn submit(self: *OrderBook, input: Order) !void {
        if (input.quantity == 0 or input.price_ticks <= 0) return error.InvalidOrder;
        var incoming = input;
        incoming.sequence = self.next_sequence;
        self.next_sequence += 1;
        const opposite = if (incoming.side == .buy) &self.asks else &self.bids;
        while (incoming.quantity > 0) {
            const best_i = bestIndex(opposite.items, if (incoming.side == .buy) .sell else .buy) orelse break;
            var resting = opposite.items[best_i];
            const crosses = if (incoming.side == .buy) incoming.price_ticks >= resting.price_ticks else incoming.price_ticks <= resting.price_ticks;
            if (!crosses) break;
            const quantity = @min(incoming.quantity, resting.quantity);
            try self.trades.append(self.allocator, .{
                .buy_order = if (incoming.side == .buy) incoming.id else resting.id,
                .sell_order = if (incoming.side == .sell) incoming.id else resting.id,
                .price_ticks = resting.price_ticks,
                .quantity = quantity,
            });
            incoming.quantity -= quantity;
            resting.quantity -= quantity;
            if (resting.quantity == 0) _ = opposite.swapRemove(best_i) else opposite.items[best_i] = resting;
        }
        if (incoming.quantity > 0 and incoming.tif == .gtc) {
            if (incoming.side == .buy) try self.bids.append(self.allocator, incoming) else try self.asks.append(self.allocator, incoming);
        }
    }

    pub fn submitMarket(self: *OrderBook, id: u64, owner: u64, side: Side, quantity: u64) !void {
        try self.submit(.{
            .id = id,
            .owner = owner,
            .side = side,
            .price_ticks = if (side == .buy) std.math.maxInt(i64) else 1,
            .quantity = quantity,
            .tif = .ioc,
        });
    }

    pub fn replace(self: *OrderBook, id: u64, replacement: Order) !void {
        if (!self.cancel(id)) return error.OrderNotFound;
        var updated = replacement;
        updated.id = id;
        try self.submit(updated);
    }

    pub fn cancel(self: *OrderBook, id: u64) bool {
        for (self.bids.items, 0..) |order, i| if (order.id == id) {
            _ = self.bids.swapRemove(i);
            return true;
        };
        for (self.asks.items, 0..) |order, i| if (order.id == id) {
            _ = self.asks.swapRemove(i);
            return true;
        };
        return false;
    }

    pub fn isUncrossed(self: *const OrderBook) bool {
        const bid_i = bestIndex(self.bids.items, .buy) orelse return true;
        const ask_i = bestIndex(self.asks.items, .sell) orelse return true;
        return self.bids.items[bid_i].price_ticks < self.asks.items[ask_i].price_ticks;
    }
};

/// Sorted-array implementation used after validating semantics against `OrderBook`.
pub const SortedOrderBook = struct {
    allocator: std.mem.Allocator,
    bids: std.ArrayList(Order) = .empty,
    asks: std.ArrayList(Order) = .empty,
    trades: std.ArrayList(Trade) = .empty,
    next_sequence: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) SortedOrderBook {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *SortedOrderBook) void {
        self.bids.deinit(self.allocator);
        self.asks.deinit(self.allocator);
        self.trades.deinit(self.allocator);
    }

    fn insert(self: *SortedOrderBook, list: *std.ArrayList(Order), side: Side, order: Order) !void {
        var index: usize = 0;
        while (index < list.items.len and !OrderBook.better(side, order, list.items[index])) : (index += 1) {}
        try list.insert(self.allocator, index, order);
    }

    pub fn submit(self: *SortedOrderBook, input: Order) !void {
        if (input.quantity == 0 or input.price_ticks <= 0) return error.InvalidOrder;
        var incoming = input;
        incoming.sequence = self.next_sequence;
        self.next_sequence += 1;
        const opposite = if (incoming.side == .buy) &self.asks else &self.bids;
        while (incoming.quantity > 0 and opposite.items.len > 0) {
            var resting = opposite.items[0];
            const crosses = if (incoming.side == .buy) incoming.price_ticks >= resting.price_ticks else incoming.price_ticks <= resting.price_ticks;
            if (!crosses) break;
            const quantity = @min(incoming.quantity, resting.quantity);
            try self.trades.append(self.allocator, .{
                .buy_order = if (incoming.side == .buy) incoming.id else resting.id,
                .sell_order = if (incoming.side == .sell) incoming.id else resting.id,
                .price_ticks = resting.price_ticks,
                .quantity = quantity,
            });
            incoming.quantity -= quantity;
            resting.quantity -= quantity;
            if (resting.quantity == 0) _ = opposite.orderedRemove(0) else opposite.items[0] = resting;
        }
        if (incoming.quantity > 0 and incoming.tif == .gtc) {
            if (incoming.side == .buy) try self.insert(&self.bids, .buy, incoming) else try self.insert(&self.asks, .sell, incoming);
        }
    }
};

pub const Bid = struct { bidder: u64, value: i64, sequence: u64 };
pub const AuctionResult = struct { winner: u64, payment: i64 };

pub fn secondPrice(bids: []const Bid) ?AuctionResult {
    if (bids.len == 0) return null;
    var first: usize = 0;
    var second: ?usize = null;
    for (bids, 0..) |bid, i| {
        if (i == first) continue;
        if (bid.value > bids[first].value or (bid.value == bids[first].value and bid.sequence < bids[first].sequence)) {
            second = first;
            first = i;
        } else if (second == null or bid.value > bids[second.?].value) second = i;
    }
    return .{ .winner = bids[first].bidder, .payment = if (second) |i| bids[i].value else 0 };
}

pub fn firstPrice(bids: []const Bid) ?AuctionResult {
    const second = secondPrice(bids) orelse return null;
    for (bids) |bid| if (bid.bidder == second.winner) return .{ .winner = bid.bidder, .payment = bid.value };
    unreachable;
}

pub fn englishAuction(bids: []const Bid, reserve: i64, increment: i64) ?AuctionResult {
    if (increment <= 0) return null;
    const result = secondPrice(bids) orelse return null;
    var winner_value: i64 = 0;
    for (bids) |bid| if (bid.bidder == result.winner) {
        winner_value = bid.value;
        break;
    };
    if (winner_value < reserve) return null;
    return .{ .winner = result.winner, .payment = @min(winner_value, @max(reserve, result.payment + increment)) };
}

pub const Acceptance = struct { bidder: u64, clock_price: i64, sequence: u64 };
pub fn dutchAuction(acceptances: []const Acceptance, reserve: i64) ?AuctionResult {
    var best: ?Acceptance = null;
    for (acceptances) |acceptance| {
        if (acceptance.clock_price < reserve) continue;
        if (best == null or acceptance.sequence < best.?.sequence) best = acceptance;
    }
    const accepted = best orelse return null;
    return .{ .winner = accepted.bidder, .payment = accepted.clock_price };
}

pub const DoubleAuctionTrade = struct { buyer: u64, seller: u64, price: i64, quantity: u64 };
fn auctionBetter(side: Side, a: Order, b: Order) bool {
    if (a.price_ticks != b.price_ticks) return if (side == .buy) a.price_ticks > b.price_ticks else a.price_ticks < b.price_ticks;
    return a.sequence < b.sequence;
}
pub fn clearDoubleAuction(buys: []const Order, sells: []const Order, output: []DoubleAuctionTrade) usize {
    var count: usize = 0;
    var used_buys = [_]bool{false} ** 128;
    var used_sells = [_]bool{false} ** 128;
    if (buys.len > used_buys.len or sells.len > used_sells.len) return 0;
    while (count < output.len) {
        var best_buy: ?usize = null;
        var best_sell: ?usize = null;
        for (buys, 0..) |order, i| if (!used_buys[i] and (best_buy == null or auctionBetter(.buy, order, buys[best_buy.?]))) {
            best_buy = i;
        };
        for (sells, 0..) |order, i| if (!used_sells[i] and (best_sell == null or auctionBetter(.sell, order, sells[best_sell.?]))) {
            best_sell = i;
        };
        if (best_buy == null or best_sell == null or buys[best_buy.?].price_ticks < sells[best_sell.?].price_ticks) break;
        const buy = buys[best_buy.?];
        const sell = sells[best_sell.?];
        output[count] = .{ .buyer = buy.owner, .seller = sell.owner, .price = @divTrunc(buy.price_ticks + sell.price_ticks, 2), .quantity = @min(buy.quantity, sell.quantity) };
        used_buys[best_buy.?] = true;
        used_sells[best_sell.?] = true;
        count += 1;
    }
    return count;
}

test "limit order book enforces price-time priority and partial fills" {
    var book = OrderBook.init(std.testing.allocator);
    defer book.deinit();
    try book.submit(.{ .id = 1, .owner = 1, .side = .sell, .price_ticks = 100, .quantity = 5 });
    try book.submit(.{ .id = 2, .owner = 2, .side = .sell, .price_ticks = 100, .quantity = 5 });
    try book.submit(.{ .id = 3, .owner = 3, .side = .buy, .price_ticks = 101, .quantity = 7 });
    try std.testing.expectEqual(@as(usize, 2), book.trades.items.len);
    try std.testing.expectEqual(@as(u64, 1), book.trades.items[0].sell_order);
    try std.testing.expectEqual(@as(u64, 2), book.trades.items[1].sell_order);
    try std.testing.expectEqual(@as(u64, 3), book.asks.items[0].quantity);
    try std.testing.expect(book.isUncrossed());
}

test "second price auction is deterministic" {
    const result = secondPrice(&.{
        .{ .bidder = 1, .value = 100, .sequence = 1 },
        .{ .bidder = 2, .value = 100, .sequence = 0 },
        .{ .bidder = 3, .value = 80, .sequence = 2 },
    }).?;
    try std.testing.expectEqual(@as(u64, 2), result.winner);
    try std.testing.expectEqual(@as(i64, 100), result.payment);
}

test "market, IOC, cancellation, and replacement obey lifecycle rules" {
    var book = OrderBook.init(std.testing.allocator);
    defer book.deinit();
    try book.submit(.{ .id = 1, .owner = 1, .side = .sell, .price_ticks = 100, .quantity = 2 });
    try book.submitMarket(2, 2, .buy, 3);
    try std.testing.expectEqual(@as(u64, 2), book.trades.items[0].quantity);
    try std.testing.expectEqual(@as(usize, 0), book.bids.items.len);
    try book.submit(.{ .id = 3, .owner = 3, .side = .buy, .price_ticks = 90, .quantity = 1 });
    try book.replace(3, .{ .id = 0, .owner = 3, .side = .buy, .price_ticks = 95, .quantity = 2 });
    try std.testing.expectEqual(@as(i64, 95), book.bids.items[0].price_ticks);
    try std.testing.expect(book.cancel(3));
}

test "standard auction payments and double auction conservation" {
    const bids = [_]Bid{
        .{ .bidder = 1, .value = 100, .sequence = 0 },
        .{ .bidder = 2, .value = 80, .sequence = 1 },
    };
    try std.testing.expectEqual(@as(i64, 100), firstPrice(&bids).?.payment);
    try std.testing.expectEqual(@as(i64, 81), englishAuction(&bids, 50, 1).?.payment);
    try std.testing.expectEqual(@as(u64, 2), dutchAuction(&.{
        .{ .bidder = 1, .clock_price = 90, .sequence = 3 },
        .{ .bidder = 2, .clock_price = 85, .sequence = 2 },
    }, 50).?.winner);
    var trades: [2]DoubleAuctionTrade = undefined;
    const count = clearDoubleAuction(&.{.{ .id = 1, .owner = 1, .side = .buy, .price_ticks = 110, .quantity = 4 }}, &.{.{ .id = 2, .owner = 2, .side = .sell, .price_ticks = 90, .quantity = 3 }}, &trades);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 3), trades[0].quantity);
}

test "sorted and reference books agree on randomized command traces" {
    var reference = OrderBook.init(std.testing.allocator);
    defer reference.deinit();
    var sorted = SortedOrderBook.init(std.testing.allocator);
    defer sorted.deinit();
    var stream = std.Random.DefaultPrng.init(0xEC0A0B1C);
    const random = stream.random();
    for (0..500) |i| {
        const order = Order{
            .id = i + 1,
            .owner = random.intRangeAtMost(u64, 1, 20),
            .side = if (random.boolean()) .buy else .sell,
            .price_ticks = random.intRangeAtMost(i64, 80, 120),
            .quantity = random.intRangeAtMost(u64, 1, 10),
            .tif = if (random.intRangeAtMost(u8, 0, 4) == 0) .ioc else .gtc,
        };
        try reference.submit(order);
        try sorted.submit(order);
    }
    try std.testing.expectEqual(reference.trades.items.len, sorted.trades.items.len);
    for (reference.trades.items, sorted.trades.items) |a, b| try std.testing.expectEqualDeep(a, b);
    try std.testing.expectEqual(reference.bids.items.len, sorted.bids.items.len);
    try std.testing.expectEqual(reference.asks.items.len, sorted.asks.items.len);
    for (sorted.bids.items[1..], sorted.bids.items[0 .. sorted.bids.items.len - 1]) |current, previous| try std.testing.expect(!OrderBook.better(.buy, current, previous));
    for (sorted.asks.items[1..], sorted.asks.items[0 .. sorted.asks.items.len - 1]) |current, previous| try std.testing.expect(!OrderBook.better(.sell, current, previous));
}
