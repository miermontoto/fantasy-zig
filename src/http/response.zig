//! utilidades de respuesta HTTP
//! helpers para formatear respuestas JSON estándar

const std = @import("std");
const httpz = @import("httpz");
const date_utils = @import("../utils/date.zig");

/// envía una respuesta exitosa con formato estándar
/// { status: "success", data: T, meta: { timestamp } }
pub fn sendSuccess(
    allocator: std.mem.Allocator,
    res: *httpz.Response,
    data: anytype,
) !void {
    const timestamp = try date_utils.getCurrentTimestamp(allocator);
    defer allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = data,
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}

/// envía una respuesta exitosa con meta personalizado
/// { status: "success", data: T, meta: M }
pub fn sendSuccessWithMeta(
    res: *httpz.Response,
    data: anytype,
    meta: anytype,
) !void {
    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = data,
        .meta = meta,
    }, .{});
}

/// envía una respuesta de error con formato estándar
pub fn sendError(
    res: *httpz.Response,
    status: std.http.Status,
    message: []const u8,
    err: ?anyerror,
) !void {
    res.setStatus(status);
    res.content_type = .JSON;

    if (err) |e| {
        try res.json(.{
            .status = "error",
            .message = message,
            .@"error" = @errorName(e),
        }, .{});
    } else {
        try res.json(.{
            .status = "error",
            .message = message,
        }, .{});
    }
}

/// envía un error 500 Internal Server Error
pub fn sendInternalError(
    res: *httpz.Response,
    message: []const u8,
    err: anyerror,
) !void {
    try sendError(res, .internal_server_error, message, err);
}

/// envía un error 400 Bad Request
pub fn sendBadRequest(
    res: *httpz.Response,
    message: []const u8,
) !void {
    try sendError(res, .bad_request, message, null);
}

/// envía un error 404 Not Found
pub fn sendNotFound(
    res: *httpz.Response,
    message: []const u8,
) !void {
    try sendError(res, .not_found, message, null);
}

test "sendSuccess formats correctly" {
    // test básico de compilación - verificar que el código compila
    _ = sendSuccess;
}
