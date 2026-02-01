const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    // Parse JSON body
    const body = req.body() orelse {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Request body is required",
        }, .{});
        return;
    };

    // Try to parse as form data or JSON
    var community_id: ?[]const u8 = null;
    var token: ?[]const u8 = null;

    // Try form data first
    community_id = req.param("id");
    token = req.param("token");

    // If not in params, try to parse body as JSON
    if (community_id == null or token == null) {
        const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, body, .{}) catch {
            res.setStatus(.bad_request);
            try res.json(.{
                .status = "error",
                .message = "Invalid JSON body",
            }, .{});
            return;
        };
        defer parsed.deinit();

        if (parsed.value == .object) {
            if (parsed.value.object.get("id")) |id| {
                if (id == .string) {
                    community_id = id.string;
                } else if (id == .integer) {
                    community_id = try std.fmt.allocPrint(ctx.allocator, "{d}", .{id.integer});
                }
            }
            if (parsed.value.object.get("token")) |t| {
                if (t == .string) {
                    token = t.string;
                }
            }
        }
    }

    if (community_id == null or token == null) {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Missing parameters: id and token are required",
        }, .{});
        return;
    }

    // Set the XAuth token
    ctx.token_service.setXAuth(community_id.?, token.?) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to save token",
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
            .community_id = community_id.?,
            .message = "XAuth token saved successfully",
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
