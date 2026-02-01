const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");
const Position = @import("../models/position.zig").Position;

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    // Get query parameters for filtering
    const qs = try req.query();
    const position_filter = qs.get("position");
    const max_price_str = qs.get("max_price");
    const search = qs.get("search");
    const source = qs.get("source");
    const own_players = qs.get("own_players");
    const sort_by = qs.get("sort_by") orelse "points";
    const sort_dir = qs.get("sort_dir") orelse "desc";

    _ = position_filter;
    _ = max_price_str;
    _ = search;
    _ = source;
    _ = own_players;
    _ = sort_by;
    _ = sort_dir;

    // Fetch market HTML
    const html = browser.market() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch market",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(html);

    // Parse balance info
    const balance_info = @import("../services/scraper.zig").Scraper.parseBalanceInfo(html);

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .players = &[_]u8{}, // TODO: Full HTML parsing
            .info = .{
                .current_balance = balance_info.current_balance,
                .future_balance = balance_info.future_balance,
                .max_debt = balance_info.max_debt,
            },
        },
        .meta = .{
            .timestamp = timestamp,
            .note = "Full player parsing requires HTML parser integration",
        },
    }, .{});
}
