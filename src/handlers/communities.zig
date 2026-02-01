const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

pub fn handleList(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Fetch communities via AJAX
    const json_response = browser.communities() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch communities",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json_response);

    // Parse communities
    const result = scraper.parseCommunities(json_response) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse communities",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    const current_community = ctx.token_service.getCurrentCommunity();

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .communities = result.communities,
            .count = result.communities.len,
        },
        .meta = .{
            .timestamp = timestamp,
            .current_community = current_community,
            .settings_hash = result.settings_hash,
            .commit_sha = result.commit_sha,
        },
    }, .{});
}

pub fn handleSwitch(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    // Get community ID from URL parameter
    const community_id = req.param("id") orelse {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Community ID is required",
        }, .{});
        return;
    };

    // Switch community
    browser.changeCommunity(community_id) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to switch community",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .community_id = community_id,
            .message = "Community switched successfully",
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
