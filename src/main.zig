const std = @import("std");
const config = @import("config.zig");
const TokenService = @import("services/token.zig").TokenService;
const server = @import("http/server.zig");

// Re-export modules for testing
pub const models = struct {
    pub const position = @import("models/position.zig");
    pub const status = @import("models/status.zig");
    pub const trend = @import("models/trend.zig");
    pub const player = @import("models/player.zig");
    pub const user = @import("models/user.zig");
    pub const community = @import("models/community.zig");
    pub const event = @import("models/event.zig");
};

pub const services = struct {
    pub const token = @import("services/token.zig");
    pub const browser = @import("services/browser.zig");
    pub const scraper = @import("services/scraper.zig");
};

pub const utils = struct {
    pub const format = @import("utils/format.zig");
    pub const date = @import("utils/date.zig");
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Print startup banner
    const cfg = config.Config.init();
    std.log.info("Fantasy Zig API Service", .{});
    std.log.info("========================", .{});
    std.log.info("Port: {d}", .{cfg.port});
    std.log.info("Host: {s}", .{cfg.host});
    std.log.info("Tokens file: {s}", .{cfg.tokens_file});

    // Initialize token service
    var token_service = TokenService.init(allocator) catch |err| {
        std.log.err("Failed to initialize token service: {}", .{err});
        return err;
    };

    // Check for refresh token
    if (token_service.getRefreshToken()) |_| {
        std.log.info("Refresh token: configured", .{});
    } else {
        std.log.warn("Refresh token: NOT configured (set REFRESH env var)", .{});
    }

    // Check for current community
    if (token_service.getCurrentCommunity()) |community| {
        std.log.info("Current community: {s}", .{community});
    } else {
        std.log.info("Current community: not set", .{});
    }

    std.log.info("", .{});
    std.log.info("Starting HTTP server...", .{});

    // Start the server
    server.startServer(allocator, &token_service) catch |err| {
        std.log.err("Server error: {}", .{err});
        return err;
    };
}

// Tests
test "all tests" {
    // Import test modules
    _ = @import("models/position.zig");
    _ = @import("models/status.zig");
    _ = @import("models/trend.zig");
    _ = @import("models/player.zig");
    _ = @import("utils/format.zig");
    _ = @import("utils/date.zig");
}
