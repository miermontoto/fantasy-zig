const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    try ctx.sendSuccess(res, .{
        .service = "fantasy-zig",
        .healthy = true,
    });
}
