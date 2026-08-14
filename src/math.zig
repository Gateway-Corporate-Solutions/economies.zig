//! Numerical utilities required by validated economic models.

const std = @import("std");

pub const MathError = error{ NotBracketed, InvalidBounds, DidNotConverge };

pub fn bisect(context: anytype, comptime f: fn (@TypeOf(context), f64) f64, lower: f64, upper: f64, tolerance: f64, max_iterations: usize) MathError!f64 {
    if (!(lower < upper) or !(tolerance > 0)) return error.InvalidBounds;
    var lo = lower;
    var hi = upper;
    var flo = f(context, lo);
    if (flo == 0) return lo;
    if (flo * f(context, hi) > 0) return error.NotBracketed;
    for (0..max_iterations) |_| {
        const mid = lo + (hi - lo) / 2.0;
        const fmid = f(context, mid);
        if (@abs(fmid) <= tolerance or (hi - lo) / 2.0 <= tolerance) return mid;
        if (flo * fmid <= 0) hi = mid else {
            lo = mid;
            flo = fmid;
        }
    }
    return error.DidNotConverge;
}

pub const OnlineStats = struct {
    count: u64 = 0,
    mean: f64 = 0,
    m2: f64 = 0,

    pub fn add(self: *OnlineStats, value: f64) void {
        self.count += 1;
        const delta = value - self.mean;
        self.mean += delta / @as(f64, @floatFromInt(self.count));
        self.m2 += delta * (value - self.mean);
    }
    pub fn variance(self: OnlineStats) ?f64 {
        if (self.count < 2) return null;
        return self.m2 / @as(f64, @floatFromInt(self.count - 1));
    }
};

pub fn linearInterpolate(x0: f64, y0: f64, x1: f64, y1: f64, x: f64) MathError!f64 {
    if (!(x0 < x1) or x < x0 or x > x1) return error.InvalidBounds;
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
}

pub fn goldenSectionMinimize(context: anytype, comptime f: fn (@TypeOf(context), f64) f64, lower: f64, upper: f64, tolerance: f64, max_iterations: usize) MathError!f64 {
    if (!(lower < upper) or tolerance <= 0) return error.InvalidBounds;
    const ratio = (@sqrt(5.0) - 1.0) / 2.0;
    var a = lower;
    var b = upper;
    var c = b - ratio * (b - a);
    var d = a + ratio * (b - a);
    for (0..max_iterations) |_| {
        if (@abs(b - a) <= tolerance) return (a + b) / 2.0;
        if (f(context, c) < f(context, d)) {
            b = d;
            d = c;
            c = b - ratio * (b - a);
        } else {
            a = c;
            c = d;
            d = a + ratio * (b - a);
        }
    }
    return error.DidNotConverge;
}

pub fn sampleStandardNormal(random: std.Random) f64 {
    const uniform_a = @max(random.float(f64), std.math.floatMin(f64));
    const uniform_b = random.float(f64);
    return @sqrt(-2.0 * @log(uniform_a)) * @cos(2.0 * std.math.pi * uniform_b);
}

test "bisection solves a bracketed root" {
    const f = struct {
        fn call(_: void, x: f64) f64 {
            return x * x - 2.0;
        }
    }.call;
    const root = try bisect({}, f, 0, 2, 1e-12, 100);
    try std.testing.expectApproxEqAbs(@sqrt(2.0), root, 1e-10);
}

test "online statistics match sample fixture" {
    var stats = OnlineStats{};
    for ([_]f64{ 1, 2, 3, 4 }) |value| stats.add(value);
    try std.testing.expectApproxEqAbs(2.5, stats.mean, 1e-12);
    try std.testing.expectApproxEqAbs(5.0 / 3.0, stats.variance().?, 1e-12);
}

test "bounded optimization finds a convex minimum" {
    const f = struct {
        fn call(_: void, x: f64) f64 {
            return (x - 3.0) * (x - 3.0);
        }
    }.call;
    try std.testing.expectApproxEqAbs(3.0, try goldenSectionMinimize({}, f, -10, 10, 1e-10, 200), 1e-8);
}
