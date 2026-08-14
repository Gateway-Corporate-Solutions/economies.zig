//! Exact fixed-point money, double-entry journals, portfolios, and settlement.

const std = @import("std");

pub const Currency = enum(u8) { USD, EUR, GBP, JPY };
pub const AccountId = u32;
pub const AssetId = u32;

pub const AccountingError = error{
    CurrencyMismatch,
    Overflow,
    UnbalancedTransaction,
    InvalidAmount,
    InsufficientFunds,
    InsufficientQuantity,
};

pub const Money = struct {
    currency: Currency,
    minor: i64,

    pub fn zero(currency: Currency) Money {
        return .{ .currency = currency, .minor = 0 };
    }
    pub fn add(self: Money, other: Money) AccountingError!Money {
        if (self.currency != other.currency) return error.CurrencyMismatch;
        return .{ .currency = self.currency, .minor = std.math.add(i64, self.minor, other.minor) catch return error.Overflow };
    }
    pub fn sub(self: Money, other: Money) AccountingError!Money {
        if (self.currency != other.currency) return error.CurrencyMismatch;
        return .{ .currency = self.currency, .minor = std.math.sub(i64, self.minor, other.minor) catch return error.Overflow };
    }
    pub fn toFloat(self: Money, scale: u32) AccountingError!f64 {
        if (scale == 0) return error.InvalidAmount;
        return @as(f64, @floatFromInt(self.minor)) / @as(f64, @floatFromInt(scale));
    }
};

pub const Posting = struct { account: AccountId, amount: Money };

pub const Journal = struct {
    allocator: std.mem.Allocator,
    postings: std.ArrayList(Posting) = .empty,
    transaction_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Journal {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Journal) void {
        self.postings.deinit(self.allocator);
    }

    pub fn post(self: *Journal, entries: []const Posting) !void {
        if (entries.len < 2) return error.UnbalancedTransaction;
        var totals = [_]i128{0} ** 4;
        for (entries) |entry| totals[@intFromEnum(entry.amount.currency)] += entry.amount.minor;
        for (totals) |total| if (total != 0) return error.UnbalancedTransaction;
        try self.postings.appendSlice(self.allocator, entries);
        self.transaction_count += 1;
    }

    pub fn balance(self: *const Journal, account: AccountId, currency: Currency) AccountingError!Money {
        var total: i64 = 0;
        for (self.postings.items) |posting| if (posting.account == account and posting.amount.currency == currency) {
            total = std.math.add(i64, total, posting.amount.minor) catch return error.Overflow;
        };
        return .{ .currency = currency, .minor = total };
    }

    pub fn sequenceHash(self: *const Journal) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.postings.items));
    }
};

pub const Position = struct { asset: AssetId, lots: i64 };

pub const Portfolio = struct {
    allocator: std.mem.Allocator,
    positions: std.ArrayList(Position) = .empty,

    pub fn init(allocator: std.mem.Allocator) Portfolio {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Portfolio) void {
        self.positions.deinit(self.allocator);
    }
    pub fn quantity(self: *const Portfolio, asset: AssetId) i64 {
        for (self.positions.items) |position| if (position.asset == asset) return position.lots;
        return 0;
    }
    pub fn ensureAsset(self: *Portfolio, asset: AssetId) !void {
        for (self.positions.items) |position| if (position.asset == asset) return;
        try self.positions.append(self.allocator, .{ .asset = asset, .lots = 0 });
    }
    pub fn transfer(self: *Portfolio, asset: AssetId, delta: i64) !void {
        for (self.positions.items) |*position| if (position.asset == asset) {
            const next = std.math.add(i64, position.lots, delta) catch return error.Overflow;
            if (next < 0) return error.InsufficientQuantity;
            position.lots = next;
            return;
        };
        if (delta < 0) return error.InsufficientQuantity;
        try self.positions.append(self.allocator, .{ .asset = asset, .lots = delta });
    }
};

pub fn transferCash(journal: *Journal, from: AccountId, to: AccountId, amount: Money) !void {
    if (amount.minor <= 0) return error.InvalidAmount;
    const debit = Money{ .currency = amount.currency, .minor = -amount.minor };
    try journal.post(&.{ .{ .account = from, .amount = debit }, .{ .account = to, .amount = amount } });
}

pub fn settleTrade(
    journal: *Journal,
    buyer_account: AccountId,
    seller_account: AccountId,
    buyer: *Portfolio,
    seller: *Portfolio,
    asset: AssetId,
    lots: i64,
    cash: Money,
) !void {
    if (lots <= 0 or cash.minor <= 0) return error.InvalidAmount;
    if (seller.quantity(asset) < lots) return error.InsufficientQuantity;
    _ = std.math.add(i64, buyer.quantity(asset), lots) catch return error.Overflow;
    try buyer.ensureAsset(asset);
    try transferCash(journal, buyer_account, seller_account, cash);
    seller.transfer(asset, -lots) catch unreachable;
    buyer.transfer(asset, lots) catch unreachable;
}

test "double-entry journal rejects imbalance and reconciles transfers" {
    var journal = Journal.init(std.testing.allocator);
    defer journal.deinit();
    try std.testing.expectError(error.UnbalancedTransaction, journal.post(&.{
        .{ .account = 1, .amount = .{ .currency = .USD, .minor = 10 } },
        .{ .account = 2, .amount = .{ .currency = .USD, .minor = -9 } },
    }));
    try transferCash(&journal, 1, 2, .{ .currency = .USD, .minor = 500 });
    try std.testing.expectEqual(@as(i64, -500), (try journal.balance(1, .USD)).minor);
    try std.testing.expectEqual(@as(i64, 500), (try journal.balance(2, .USD)).minor);
}

test "money never silently crosses currencies or overflows" {
    try std.testing.expectError(error.CurrencyMismatch, (Money{ .currency = .USD, .minor = 1 }).add(.{ .currency = .EUR, .minor = 1 }));
    try std.testing.expectError(error.Overflow, (Money{ .currency = .USD, .minor = std.math.maxInt(i64) }).add(.{ .currency = .USD, .minor = 1 }));
}

test "trade settlement conserves cash postings and asset lots" {
    var journal = Journal.init(std.testing.allocator);
    defer journal.deinit();
    var buyer = Portfolio.init(std.testing.allocator);
    defer buyer.deinit();
    var seller = Portfolio.init(std.testing.allocator);
    defer seller.deinit();
    try seller.transfer(7, 10);
    try settleTrade(&journal, 1, 2, &buyer, &seller, 7, 4, .{ .currency = .USD, .minor = 500 });
    try std.testing.expectEqual(@as(i64, 4), buyer.quantity(7));
    try std.testing.expectEqual(@as(i64, 6), seller.quantity(7));
    try std.testing.expectEqual(@as(i64, 0), (try journal.balance(1, .USD)).minor + (try journal.balance(2, .USD)).minor);
}
