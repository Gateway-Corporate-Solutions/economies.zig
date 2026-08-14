const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const economies = b.addModule("economies", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli = b.addExecutable(.{
        .name = "economies",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "economies", .module = economies }},
        }),
    });
    b.installArtifact(cli);

    const unit_tests = b.addTest(.{ .root_module = economies });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all unit, invariant, and reference tests");
    test_step.dependOn(&run_tests.step);

    const examples_step = b.step("examples", "Compile all examples");
    const example_specs = .{
        .{ "three-models", "examples/three_models.zig" },
        .{ "micro-demand", "examples/micro_demand.zig" },
        .{ "micro-walras", "examples/micro_walras.zig" },
        .{ "micro-auction", "examples/micro_auction.zig" },
        .{ "macro-solow", "examples/macro_solow.zig" },
        .{ "macro-rbc", "examples/macro_rbc.zig" },
        .{ "macro-sfc", "examples/macro_sfc.zig" },
        .{ "backtest-buy-hold", "examples/backtest_buy_hold.zig" },
        .{ "backtest-moving-average", "examples/backtest_moving_average.zig" },
        .{ "backtest-point-in-time", "examples/backtest_point_in_time.zig" },
    };
    inline for (example_specs) |spec| {
        const example = b.addExecutable(.{
            .name = spec[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path(spec[1]),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "economies", .module = economies }},
            }),
        });
        examples_step.dependOn(&example.step);
    }

    const benchmark = b.addExecutable(.{
        .name = "economies-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "economies", .module = economies }},
        }),
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    const bench_step = b.step("bench", "Run the reproducible benchmark harness");
    bench_step.dependOn(&run_benchmark.step);

    const docs = b.addObject(.{ .name = "economies-docs", .root_module = economies });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate API documentation");
    docs_step.dependOn(&install_docs.step);

    const run_cmd = b.addRunArtifact(cli);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the economies.zig CLI");
    run_step.dependOn(&run_cmd.step);

    const all_step = b.step("all", "Build, test, examples, benchmarks, and docs");
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(test_step);
    all_step.dependOn(examples_step);
    all_step.dependOn(bench_step);
    all_step.dependOn(docs_step);
}
