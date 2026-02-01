const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");
const Scraper = @import("../services/scraper.zig").Scraper;

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Fetch feed HTML
    const html = browser.feed() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch feed",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(html);

    // Parse feed info
    const info = scraper.parseFeedInfo(html) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse feed",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    // Parse market players from feed
    const market_players = scraper.parseFeedMarket(html) catch &[_]@import("../models/player.zig").MarketPlayer{};

    // Fetch communities
    const communities_json = browser.communities() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch communities",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(communities_json);

    // Parse communities
    const communities_result = scraper.parseCommunities(communities_json) catch |err| {
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
            .info = .{
                .community = info.community,
                .balance = info.balance,
                .credits = info.credits,
                .gameweek = info.gameweek,
                .gameweek_status = info.status,
            },
            .market = market_players,
            .market_count = market_players.len,
            .communities = communities_result.communities,
            .communities_count = communities_result.communities.len,
        },
        .meta = .{
            .timestamp = timestamp,
            .current_community = current_community,
            .settings_hash = communities_result.settings_hash,
            .commit_sha = communities_result.commit_sha,
        },
    }, .{});
}
