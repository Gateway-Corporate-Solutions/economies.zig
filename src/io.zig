//! Versioned observation and CSV result schemas without hidden I/O capabilities.

const std = @import("std");
const backtest = @import("backtest.zig");
const core = @import("core.zig");

pub const schema_version: u16 = 1;
pub const Observation = struct { tick: u64, name: []const u8, value: f64 };

pub fn formatCsvRow(buffer: []u8, observation: Observation) ![]const u8 {
    if (std.mem.indexOfScalar(u8, observation.name, ',') != null or std.mem.indexOfScalar(u8, observation.name, '\n') != null) return error.InvalidField;
    return std.fmt.bufPrint(buffer, "{d},{s},{d}\n", .{ observation.tick, observation.name, observation.value });
}

pub fn parseBarCsvRow(row: []const u8) !backtest.Bar {
    var fields = std.mem.splitScalar(u8, std.mem.trim(u8, row, "\r\n"), ',');
    const timestamp = try std.fmt.parseInt(backtest.Timestamp, fields.next() orelse return error.MissingField, 10);
    const symbol = try std.fmt.parseInt(u32, fields.next() orelse return error.MissingField, 10);
    const open = try std.fmt.parseInt(i64, fields.next() orelse return error.MissingField, 10);
    const high = try std.fmt.parseInt(i64, fields.next() orelse return error.MissingField, 10);
    const low = try std.fmt.parseInt(i64, fields.next() orelse return error.MissingField, 10);
    const close = try std.fmt.parseInt(i64, fields.next() orelse return error.MissingField, 10);
    if (fields.next() != null) return error.ExtraField;
    if (open <= 0 or high < @max(open, close) or low > @min(open, close) or low <= 0) return error.InvalidBar;
    return .{ .timestamp = timestamp, .symbol = symbol, .open = open, .high = high, .low = low, .close = close };
}

pub fn formatManifest(buffer: []u8, manifest: core.Manifest) ![]const u8 {
    if (std.mem.indexOfScalar(u8, manifest.model, '"') != null) return error.InvalidField;
    return std.fmt.bufPrint(buffer, "{{\"schema_version\":{d},\"package_version\":\"{s}\",\"zig_version\":\"{s}\",\"model\":\"{s}\",\"seed\":{d},\"parameter_hash\":{d},\"input_hash\":{d},\"replay_key\":{d}}}\n", .{ manifest.schema_version, manifest.package_version, manifest.zig_version, manifest.model, manifest.seed, manifest.parameter_hash, manifest.input_hash, manifest.replayKey() });
}

test "CSV observations use a stable schema and reject ambiguous fields" {
    var buffer: [128]u8 = undefined;
    const row = try formatCsvRow(&buffer, .{ .tick = 3, .name = "capital", .value = 1.5 });
    try std.testing.expectEqualStrings("3,capital,1.5\n", row);
    try std.testing.expectError(error.InvalidField, formatCsvRow(&buffer, .{ .tick = 3, .name = "bad,name", .value = 1.5 }));
}

test "bar CSV parser validates market data geometry" {
    const bar = try parseBarCsvRow("10,7,100,110,90,105\n");
    try std.testing.expectEqual(@as(u32, 7), bar.symbol);
    try std.testing.expectError(error.InvalidBar, parseBarCsvRow("10,7,100,99,90,105"));
    try std.testing.expectError(error.ExtraField, parseBarCsvRow("10,7,100,110,90,105,extra"));
}

test "run manifest serialization is stable and contains replay key" {
    var buffer: [512]u8 = undefined;
    const text = try formatManifest(&buffer, .{ .model = "solow", .seed = 4, .parameter_hash = 5, .input_hash = 6 });
    try std.testing.expect(std.mem.indexOf(u8, text, "\"replay_key\"") != null);
}
