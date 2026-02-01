const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Fetch standings HTML
    const html = browser.standings() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch standings",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(html);

    // Parse standings
    const standings = scraper.parseStandings(html) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse standings",
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
            .total = standings.total,
            .gameweek = standings.gameweek,
            .total_count = standings.total.len,
            .gameweek_count = standings.gameweek.len,
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
