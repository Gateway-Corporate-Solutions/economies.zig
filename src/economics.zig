//! Economic entities, goods, assets, counterparties, and contract cash-flow lifecycle.

const std = @import("std");
const accounting = @import("accounting.zig");

pub const EntityId = u64;
pub const GoodId = u32;

pub const Good = struct { id: GoodId, name: []const u8 };
pub const Agent = struct { id: EntityId };
pub const Asset = struct { id: accounting.AssetId, issuer: EntityId, currency: accounting.Currency };
pub const Quantity = struct {
    asset: accounting.AssetId,
    lots: i64,
    pub fn add(self: Quantity, other: Quantity) !Quantity {
        if (self.asset != other.asset) return error.AssetMismatch;
        return .{ .asset = self.asset, .lots = std.math.add(i64, self.lots, other.lots) catch return error.Overflow };
    }
};
pub const Price = struct {
    asset: accounting.AssetId,
    quote_currency: accounting.Currency,
    minor_per_lot: i64,
};

pub fn tradeValue(price: Price, quantity: Quantity) !accounting.Money {
    if (price.asset != quantity.asset) return error.AssetMismatch;
    if (price.minor_per_lot < 0 or quantity.lots < 0) return error.InvalidAmount;
    return .{ .currency = price.quote_currency, .minor = std.math.mul(i64, price.minor_per_lot, quantity.lots) catch return error.Overflow };
}

pub const ContractState = enum { active, matured, defaulted };
pub const CashFlow = struct { due: u64, amount: accounting.Money };

pub const Loan = struct {
    lender_account: accounting.AccountId,
    borrower_account: accounting.AccountId,
    principal: accounting.Money,
    rate: f64,
    maturity: u64,
    state: ContractState = .active,

    pub fn settle(self: *Loan, now: u64, journal: *accounting.Journal) !void {
        if (self.state != .active or now < self.maturity) return;
        if (self.rate < 0) return error.InvalidAmount;
        const factor = 1.0 + self.rate;
        const due_float = @as(f64, @floatFromInt(self.principal.minor)) * factor;
        if (due_float > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return error.Overflow;
        const due: i64 = @intFromFloat(@round(due_float));
        try accounting.transferCash(journal, self.borrower_account, self.lender_account, .{
            .currency = self.principal.currency,
            .minor = due,
        });
        self.state = .matured;
    }

    pub fn default(self: *Loan) void {
        if (self.state == .active) self.state = .defaulted;
    }
};

test "loan lifecycle reconciles both counterparties" {
    var journal = accounting.Journal.init(std.testing.allocator);
    defer journal.deinit();
    var loan = Loan{
        .lender_account = 1,
        .borrower_account = 2,
        .principal = .{ .currency = .USD, .minor = 10_000 },
        .rate = 0.05,
        .maturity = 10,
    };
    try loan.settle(9, &journal);
    try std.testing.expectEqual(@as(usize, 0), journal.transaction_count);
    try loan.settle(10, &journal);
    try std.testing.expectEqual(ContractState.matured, loan.state);
    try std.testing.expectEqual(@as(i64, 10_500), (try journal.balance(1, .USD)).minor);
    try std.testing.expectEqual(@as(i64, -10_500), (try journal.balance(2, .USD)).minor);
}

test "typed prices and quantities reject asset mixing" {
    const value = try tradeValue(.{ .asset = 1, .quote_currency = .USD, .minor_per_lot = 250 }, .{ .asset = 1, .lots = 4 });
    try std.testing.expectEqual(@as(i64, 1_000), value.minor);
    try std.testing.expectError(error.AssetMismatch, tradeValue(.{ .asset = 1, .quote_currency = .USD, .minor_per_lot = 250 }, .{ .asset = 2, .lots = 4 }));
}
