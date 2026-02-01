const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Get interval from query parameter (default: day)
    const qs = try req.query();
    const interval = qs.get("interval") orelse "day";

    // Validate interval
    const valid_intervals = [_][]const u8{ "day", "week", "month" };
    var is_valid = false;
    for (valid_intervals) |v| {
        if (std.mem.eql(u8, interval, v)) {
            is_valid = true;
            break;
        }
    }

    if (!is_valid) {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Invalid interval. Must be one of: day, week, month",
        }, .{});
        return;
    }

    // Fetch top market via AJAX
    const json_response = browser.topMarket(interval) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch top market",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json_response);

    // Parse top market
    const result = scraper.parseTopMarket(json_response, interval) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse top market",
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
            .positive = result.positive,
            .negative = result.negative,
            .last_value = result.last_value,
            .last_date = result.last_date,
            .diff = result.diff,
        },
        .meta = .{
            .timestamp = timestamp,
            .interval = interval,
        },
    }, .{});
}
