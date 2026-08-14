//! Deterministic parameter grids, replications, resumable results, and confidence summaries.

const std = @import("std");
const core = @import("core.zig");
const math = @import("math.zig");

pub const Parameter = struct { name: []const u8, value: f64 };
pub const Result = struct { parameter_index: usize, replication: usize, seed: u64, value: f64 };

pub fn replicationSeed(root_seed: u64, parameter_index: usize, replication: usize) u64 {
    var buffer: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&buffer, "experiment/{d}/{d}", .{ parameter_index, replication }) catch unreachable;
    return core.Stream.init(root_seed, name).seed;
}

pub fn runGrid(
    allocator: std.mem.Allocator,
    parameters: []const Parameter,
    replications: usize,
    root_seed: u64,
    comptime Model: type,
    model: Model,
    existing: []const Result,
) ![]Result {
    var results: std.ArrayList(Result) = .empty;
    errdefer results.deinit(allocator);
    try results.appendSlice(allocator, existing);
    for (parameters, 0..) |parameter, p| for (0..replications) |r| {
        var found = false;
        for (existing) |result| if (result.parameter_index == p and result.replication == r) {
            found = true;
            break;
        };
        if (!found) {
            const seed = replicationSeed(root_seed, p, r);
            try results.append(allocator, .{ .parameter_index = p, .replication = r, .seed = seed, .value = model.run(parameter.value, seed) });
        }
    };
    std.mem.sort(Result, results.items, {}, struct {
        fn lessThan(_: void, a: Result, b: Result) bool {
            return a.parameter_index < b.parameter_index or (a.parameter_index == b.parameter_index and a.replication < b.replication);
        }
    }.lessThan);
    return results.toOwnedSlice(allocator);
}

pub fn summarize(results: []const Result) math.OnlineStats {
    var stats = math.OnlineStats{};
    for (results) |result| stats.add(result.value);
    return stats;
}

pub const ConfidenceInterval = struct { mean: f64, lower: f64, upper: f64 };
pub fn confidence95(results: []const Result) !ConfidenceInterval {
    const stats = summarize(results);
    const variance = stats.variance() orelse return error.InsufficientData;
    const half_width = 1.96 * @sqrt(variance / @as(f64, @floatFromInt(stats.count)));
    return .{ .mean = stats.mean, .lower = stats.mean - half_width, .upper = stats.mean + half_width };
}

pub const CalibrationResult = struct { parameter: f64, loss: f64 };
pub fn calibrateGrid(candidates: []const f64, context: anytype, comptime lossFn: fn (@TypeOf(context), f64) f64) !CalibrationResult {
    if (candidates.len == 0) return error.NoCandidates;
    var best = CalibrationResult{ .parameter = candidates[0], .loss = lossFn(context, candidates[0]) };
    for (candidates[1..]) |candidate| {
        const loss = lossFn(context, candidate);
        if (loss < best.loss) best = .{ .parameter = candidate, .loss = loss };
    }
    return best;
}

test "resumed experiment does not recompute completed runs and stays ordered" {
    const Model = struct {
        fn run(_: @This(), parameter: f64, seed: u64) f64 {
            return parameter + @as(f64, @floatFromInt(seed % 10));
        }
    };
    const parameters = [_]Parameter{ .{ .name = "s", .value = 0.1 }, .{ .name = "s", .value = 0.2 } };
    const first = try runGrid(std.testing.allocator, &parameters, 1, 7, Model, .{}, &.{});
    defer std.testing.allocator.free(first);
    const resumed = try runGrid(std.testing.allocator, &parameters, 2, 7, Model, .{}, first);
    defer std.testing.allocator.free(resumed);
    try std.testing.expectEqual(@as(usize, 4), resumed.len);
    try std.testing.expectEqual(first[0].seed, resumed[0].seed);
    try std.testing.expect(resumed[0].parameter_index <= resumed[1].parameter_index);
}

test "thousand-run sweep is deterministic, resumable, and summarized" {
    const Model = struct {
        fn run(_: @This(), parameter: f64, seed: u64) f64 {
            return parameter + @as(f64, @floatFromInt(seed % 100)) / 100.0;
        }
    };
    const parameters = [_]Parameter{.{ .name = "p", .value = 1.0 }};
    const complete = try runGrid(std.testing.allocator, &parameters, 1_000, 99, Model, .{}, &.{});
    defer std.testing.allocator.free(complete);
    const resumed = try runGrid(std.testing.allocator, &parameters, 1_000, 99, Model, .{}, complete[0..500]);
    defer std.testing.allocator.free(resumed);
    try std.testing.expectEqualDeep(complete, resumed);
    const interval = try confidence95(complete);
    try std.testing.expect(interval.lower < interval.mean and interval.mean < interval.upper);
}

test "calibration interface is optimizer-independent" {
    const loss = struct {
        fn call(target: f64, value: f64) f64 {
            return (value - target) * (value - target);
        }
    }.call;
    const result = try calibrateGrid(&.{ 1, 2, 3, 4 }, @as(f64, 3.1), loss);
    try std.testing.expectEqual(@as(f64, 3), result.parameter);
}
