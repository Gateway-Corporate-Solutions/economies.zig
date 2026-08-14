//! Deterministic identifiers, clocks, random streams, scheduling, and replay manifests.

const std = @import("std");

pub const Tick = u64;

pub fn Id(comptime Tag: type) type {
    return struct {
        value: u64,
        pub const tag = Tag;
        const Self = @This();
        pub fn init(value: u64) Self {
            return .{ .value = value };
        }
    };
}

pub const Stream = struct {
    seed: u64,
    prng: std.Random.DefaultPrng,

    pub fn init(root_seed: u64, name: []const u8) Stream {
        const seed = std.hash.Wyhash.hash(root_seed, name);
        return .{ .seed = seed, .prng = std.Random.DefaultPrng.init(seed) };
    }

    pub fn random(self: *Stream) std.Random {
        return self.prng.random();
    }

    pub fn checkpoint(self: *const Stream) std.Random.DefaultPrng {
        return self.prng;
    }
    pub fn restore(self: *Stream, state: std.Random.DefaultPrng) void {
        self.prng = state;
    }
};

pub fn EventQueue(comptime Payload: type) type {
    return struct {
        const Self = @This();
        pub const Event = struct { id: u64, at: Tick, sequence: u64, payload: Payload };
        pub const Checkpoint = struct {
            events: []Event,
            next_id: u64,
            next_sequence: u64,
            pub fn deinit(self: Checkpoint, allocator: std.mem.Allocator) void {
                allocator.free(self.events);
            }
        };

        allocator: std.mem.Allocator,
        events: std.ArrayList(Event) = .empty,
        next_id: u64 = 1,
        next_sequence: u64 = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }
        pub fn deinit(self: *Self) void {
            self.events.deinit(self.allocator);
        }

        pub fn schedule(self: *Self, at: Tick, payload: Payload) !u64 {
            const id = self.next_id;
            self.next_id += 1;
            try self.events.append(self.allocator, .{ .id = id, .at = at, .sequence = self.next_sequence, .payload = payload });
            self.next_sequence += 1;
            return id;
        }

        pub fn cancel(self: *Self, id: u64) bool {
            for (self.events.items, 0..) |event, i| if (event.id == id) {
                _ = self.events.swapRemove(i);
                return true;
            };
            return false;
        }

        pub fn reschedule(self: *Self, id: u64, at: Tick) bool {
            for (self.events.items) |*event| if (event.id == id) {
                event.at = at;
                event.sequence = self.next_sequence;
                self.next_sequence += 1;
                return true;
            };
            return false;
        }

        pub fn pop(self: *Self) ?Event {
            if (self.events.items.len == 0) return null;
            var best: usize = 0;
            for (self.events.items[1..], 1..) |event, i| {
                const current = self.events.items[best];
                if (event.at < current.at or (event.at == current.at and event.sequence < current.sequence)) best = i;
            }
            return self.events.swapRemove(best);
        }

        pub fn checkpoint(self: *const Self, allocator: std.mem.Allocator) !Checkpoint {
            return .{
                .events = try allocator.dupe(Event, self.events.items),
                .next_id = self.next_id,
                .next_sequence = self.next_sequence,
            };
        }

        pub fn restore(self: *Self, checkpoint_state: Checkpoint) !void {
            self.events.clearRetainingCapacity();
            try self.events.appendSlice(self.allocator, checkpoint_state.events);
            self.next_id = checkpoint_state.next_id;
            self.next_sequence = checkpoint_state.next_sequence;
        }
    };
}

pub fn Simulation(comptime Payload: type) type {
    return struct {
        const Self = @This();
        pub const Queue = EventQueue(Payload);
        pub const Checkpoint = struct {
            now: Tick,
            handled: u64,
            event_hash: u64,
            queue: Queue.Checkpoint,

            pub fn deinit(self: Checkpoint, allocator: std.mem.Allocator) void {
                self.queue.deinit(allocator);
            }
        };

        queue: Queue,
        now: Tick = 0,
        handled: u64 = 0,
        event_hash: u64 = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .queue = Queue.init(allocator) };
        }
        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn runUntil(self: *Self, model: anytype, observer: anytype, until: Tick) !void {
            while (self.queue.pop()) |event| {
                if (event.at > until) {
                    try self.queue.events.append(self.queue.allocator, event);
                    break;
                }
                if (event.at < self.now) return error.TimeMovedBackward;
                self.now = event.at;
                try model.handle(event.payload, event.at);
                observer.observe(event);
                self.handled += 1;
                self.event_hash = std.hash.Wyhash.hash(self.event_hash, std.mem.asBytes(&event.id));
                self.event_hash = std.hash.Wyhash.hash(self.event_hash, std.mem.asBytes(&event.at));
                self.event_hash = std.hash.Wyhash.hash(self.event_hash, std.mem.asBytes(&event.sequence));
            }
        }

        pub fn checkpoint(self: *const Self, allocator: std.mem.Allocator) !Checkpoint {
            return .{ .now = self.now, .handled = self.handled, .event_hash = self.event_hash, .queue = try self.queue.checkpoint(allocator) };
        }

        pub fn restore(self: *Self, checkpoint_state: Checkpoint) !void {
            self.now = checkpoint_state.now;
            self.handled = checkpoint_state.handled;
            self.event_hash = checkpoint_state.event_hash;
            try self.queue.restore(checkpoint_state.queue);
        }
    };
}

pub const NullObserver = struct {
    pub fn observe(_: NullObserver, _: anytype) void {}
};

/// Runs a discrete-time model satisfying `step(tick)` through the shared public runner.
pub fn runSteps(model: anytype, observer: anytype, periods: usize) !void {
    for (0..periods) |tick| {
        try model.step(@intCast(tick));
        observer.observeStep(@intCast(tick));
    }
}

pub const NullStepObserver = struct {
    pub fn observeStep(_: NullStepObserver, _: Tick) void {}
};

pub fn ReplayBundle(comptime Payload: type, comptime Model: type) type {
    return struct {
        simulation: Simulation(Payload).Checkpoint,
        model: Model,
        random_state: std.Random.DefaultPrng,

        pub fn capture(allocator: std.mem.Allocator, simulation: *const Simulation(Payload), model: Model, stream: *const Stream) !@This() {
            return .{ .simulation = try simulation.checkpoint(allocator), .model = model, .random_state = stream.checkpoint() };
        }
        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            self.simulation.deinit(allocator);
        }
        pub fn restore(self: @This(), simulation: *Simulation(Payload), stream: *Stream) !Model {
            try simulation.restore(self.simulation);
            stream.restore(self.random_state);
            return self.model;
        }
    };
}

pub const InvariantError = error{InvariantViolated};
pub fn requireInvariant(condition: bool) InvariantError!void {
    if (!condition) return error.InvariantViolated;
}

pub const Manifest = struct {
    schema_version: u16 = 1,
    package_version: []const u8 = "0.1.0-dev.1",
    zig_version: []const u8 = @import("builtin").zig_version_string,
    model: []const u8,
    seed: u64,
    parameter_hash: u64,
    input_hash: u64,

    pub fn replayKey(self: Manifest) u64 {
        var hash = std.hash.Wyhash.init(0);
        hash.update(self.model);
        hash.update(std.mem.asBytes(&self.seed));
        hash.update(std.mem.asBytes(&self.parameter_hash));
        hash.update(std.mem.asBytes(&self.input_hash));
        return hash.final();
    }
};

test "equal-time events preserve insertion order and support replay" {
    var queue = EventQueue(u8).init(std.testing.allocator);
    defer queue.deinit();
    _ = try queue.schedule(4, 1);
    const cancelled = try queue.schedule(2, 9);
    _ = try queue.schedule(4, 2);
    try std.testing.expect(queue.cancel(cancelled));
    const snapshot = try queue.checkpoint(std.testing.allocator);
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), queue.pop().?.payload);
    try queue.restore(snapshot);
    try std.testing.expectEqual(@as(u8, 1), queue.pop().?.payload);
    try std.testing.expectEqual(@as(u8, 2), queue.pop().?.payload);
}

test "empty queue checkpoint preserves monotonic event identity" {
    var queue = EventQueue(u8).init(std.testing.allocator);
    defer queue.deinit();
    const first = try queue.schedule(0, 1);
    _ = queue.pop();
    const saved = try queue.checkpoint(std.testing.allocator);
    defer saved.deinit(std.testing.allocator);
    _ = try queue.schedule(1, 2);
    try queue.restore(saved);
    const after_restore = try queue.schedule(1, 3);
    try std.testing.expect(after_restore > first);
}

test "named random streams are independent of construction order" {
    var a1 = Stream.init(77, "household/a");
    var b1 = Stream.init(77, "household/b");
    var b2 = Stream.init(77, "household/b");
    var a2 = Stream.init(77, "household/a");
    try std.testing.expectEqual(a1.random().int(u64), a2.random().int(u64));
    try std.testing.expectEqual(b1.random().int(u64), b2.random().int(u64));
    try std.testing.expect(a1.seed != b1.seed);
}

test "observer presence cannot affect model results and checkpoint resumes exactly" {
    const Payload = union(enum) { add: i64, subtract: i64 };
    const Model = struct {
        total: i64 = 0,
        fn handle(self: *@This(), payload: Payload, _: Tick) !void {
            switch (payload) {
                .add => |value| self.total += value,
                .subtract => |value| self.total -= value,
            }
        }
    };
    const Counter = struct {
        count: *usize,
        fn observe(self: @This(), _: anytype) void {
            self.count.* += 1;
        }
    };

    var first = Simulation(Payload).init(std.testing.allocator);
    defer first.deinit();
    _ = try first.queue.schedule(1, .{ .add = 5 });
    _ = try first.queue.schedule(2, .{ .subtract = 2 });
    var model_a = Model{};
    try first.runUntil(&model_a, NullObserver{}, 1);
    const saved = try first.checkpoint(std.testing.allocator);
    defer saved.deinit(std.testing.allocator);
    try first.runUntil(&model_a, NullObserver{}, 10);

    var second = Simulation(Payload).init(std.testing.allocator);
    defer second.deinit();
    try second.restore(saved);
    var model_b = Model{ .total = 5 };
    var observations: usize = 0;
    try second.runUntil(&model_b, Counter{ .count = &observations }, 10);
    try std.testing.expectEqual(model_a.total, model_b.total);
    try std.testing.expectEqual(first.event_hash, second.event_hash);
    try std.testing.expectEqual(@as(usize, 1), observations);
}

test "replay bundle restores model, scheduler, and RNG together" {
    const Payload = enum { tick };
    const Model = struct { value: u64 };
    var simulation = Simulation(Payload).init(std.testing.allocator);
    defer simulation.deinit();
    _ = try simulation.queue.schedule(4, .tick);
    var stream = Stream.init(123, "model");
    _ = stream.random().int(u64);
    const bundle = try ReplayBundle(Payload, Model).capture(std.testing.allocator, &simulation, .{ .value = 9 }, &stream);
    defer bundle.deinit(std.testing.allocator);
    const expected_random = stream.random().int(u64);
    _ = simulation.queue.pop();
    const model = try bundle.restore(&simulation, &stream);
    try std.testing.expectEqual(@as(u64, 9), model.value);
    try std.testing.expectEqual(expected_random, stream.random().int(u64));
    try std.testing.expectEqual(@as(Tick, 4), simulation.queue.pop().?.at);
    try std.testing.expectError(error.InvariantViolated, requireInvariant(false));
}

test "discrete public runner drives model-owned state" {
    const Model = struct {
        value: u64 = 1,
        fn step(self: *@This(), tick: Tick) !void {
            self.value += tick;
        }
    };
    var model = Model{};
    try runSteps(&model, NullStepObserver{}, 4);
    try std.testing.expectEqual(@as(u64, 7), model.value);
}
