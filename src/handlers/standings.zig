const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Fetch standings HTML
    const html = browser.standings() catch |err| {
        try ctx.sendInternalError(res, "Failed to fetch standings", err);
        return;
    };
    defer ctx.allocator.free(html);

    // Parse standings
    const standings = scraper.parseStandings(html) catch |err| {
        try ctx.sendInternalError(res, "Failed to parse standings", err);
        return;
    };

    try ctx.sendSuccess(res, .{
        .total = standings.total,
        .gameweek = standings.gameweek,
        .total_count = standings.total.len,
        .gameweek_count = standings.gameweek.len,
    });
}
