const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

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

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

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
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
