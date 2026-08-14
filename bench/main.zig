const std = @import("std");
const economies = @import("economies");

pub fn main(init: std.process.Init) void {
    var started = std.Io.Timestamp.now(init.io, .awake);
    var checksum: u64 = 0;
    var buffer: [32]u8 = undefined;
    for (0..100_000) |i| {
        const name = std.fmt.bufPrint(&buffer, "stream/{d}", .{i}) catch unreachable;
        checksum +%= economies.core.Stream.init(42, name).seed;
    }
    const elapsed = started.untilNow(init.io, .awake).nanoseconds;
    std.debug.print("benchmark=stream_derivation iterations=100000 elapsed_ns={d} checksum={d}\n", .{ elapsed, checksum });

    var queue = economies.core.EventQueue(u64).init(init.gpa);
    defer queue.deinit();
    started = std.Io.Timestamp.now(init.io, .awake);
    for (0..5_000) |i| _ = queue.schedule(@intCast(i % 1_000), i) catch unreachable;
    while (queue.pop()) |event| checksum +%= event.payload;
    const queue_elapsed = started.untilNow(init.io, .awake).nanoseconds;
    std.debug.print("benchmark=event_queue operations=10000 elapsed_ns={d} checksum={d}\n", .{ queue_elapsed, checksum });

    var journal = economies.accounting.Journal.init(init.gpa);
    defer journal.deinit();
    started = std.Io.Timestamp.now(init.io, .awake);
    for (0..10_000) |_| journal.post(&.{
        .{ .account = 1, .amount = .{ .currency = .USD, .minor = -100 } },
        .{ .account = 2, .amount = .{ .currency = .USD, .minor = 100 } },
    }) catch unreachable;
    const journal_elapsed = started.untilNow(init.io, .awake).nanoseconds;
    std.debug.print("benchmark=ledger_transactions operations=10000 elapsed_ns={d} hash={d}\n", .{ journal_elapsed, journal.sequenceHash() });

    var book = economies.markets.SortedOrderBook.init(init.gpa);
    defer book.deinit();
    started = std.Io.Timestamp.now(init.io, .awake);
    for (0..20_000) |i| book.submit(.{
        .id = i + 1,
        .owner = i % 100,
        .side = if (i % 2 == 0) .buy else .sell,
        .price_ticks = @intCast(90 + i % 21),
        .quantity = 1,
    }) catch unreachable;
    const book_elapsed = started.untilNow(init.io, .awake).nanoseconds;
    std.debug.print("benchmark=sorted_order_book orders=20000 trades={d} elapsed_ns={d}\n", .{ book.trades.items.len, book_elapsed });

    started = std.Io.Timestamp.now(init.io, .awake);
    var capital: f64 = 0.5;
    const solow = economies.macro.Solow{};
    for (0..1_000_000) |_| capital = solow.step(capital);
    const solow_elapsed = started.untilNow(init.io, .awake).nanoseconds;
    std.debug.print("benchmark=solow_steps operations=1000000 elapsed_ns={d} capital={d}\n", .{ solow_elapsed, capital });
}
