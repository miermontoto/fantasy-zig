const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Fetch offers via AJAX
    const json_response = browser.offers() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch offers",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json_response);

    // Parse offers
    const result = scraper.parseOffers(json_response) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse offers",
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
            .offers = result.offers,
            .count = result.offers.len,
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
