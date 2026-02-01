const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get http.zig dependency
    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // Get mcp.zig dependency
    const mcp_dep = b.dependency("mcp", .{
        .target = target,
        .optimize = optimize,
    });

    // Main HTTP server executable
    const exe = b.addExecutable(.{
        .name = "fantasy-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "httpz", .module = httpz_dep.module("httpz") },
            },
        }),
    });

    b.installArtifact(exe);

    // MCP server executable
    const mcp_exe = b.addExecutable(.{
        .name = "fantasy-mcp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mcp_server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mcp", .module = mcp_dep.module("mcp") },
            },
        }),
    });

    b.installArtifact(mcp_exe);

    // Run command for HTTP server
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the fantasy API server");
    run_step.dependOn(&run_cmd.step);

    // Run command for MCP server
    const run_mcp_cmd = b.addRunArtifact(mcp_exe);
    run_mcp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_mcp_cmd.addArgs(args);
    }

    const run_mcp_step = b.step("run-mcp", "Run the fantasy MCP server");
    run_mcp_step.dependOn(&run_mcp_cmd.step);

    // Tests
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "httpz", .module = httpz_dep.module("httpz") },
            },
        }),
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
