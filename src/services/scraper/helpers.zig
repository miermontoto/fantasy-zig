//! funciones auxiliares para parsing de HTML y texto
//! extracción de contenido entre marcadores, atributos, números europeos

const std = @import("std");

/// extrae texto entre dos marcadores en un string HTML
/// retorna null si no encuentra el patrón
pub fn extractBetween(html: []const u8, start_marker: []const u8, end_marker: []const u8) ?[]const u8 {
    const start_idx = std.mem.indexOf(u8, html, start_marker) orelse return null;
    const content_start = start_idx + start_marker.len;
    const end_idx = std.mem.indexOf(u8, html[content_start..], end_marker) orelse return null;
    return html[content_start .. content_start + end_idx];
}

/// extrae el valor de un atributo HTML (e.g., data-id="123")
pub fn extractAttribute(html: []const u8, attr_name: []const u8) ?[]const u8 {
    const attr_search = std.fmt.allocPrint(std.heap.page_allocator, "{s}=\"", .{attr_name}) catch return null;
    defer std.heap.page_allocator.free(attr_search);

    const start_idx = std.mem.indexOf(u8, html, attr_search) orelse return null;
    const value_start = start_idx + attr_search.len;
    const end_idx = std.mem.indexOf(u8, html[value_start..], "\"") orelse return null;
    return html[value_start .. value_start + end_idx];
}

/// parsea número con formato europeo (1.234.567 → 1234567)
pub fn parseEuropeanNumber(text: []const u8) i64 {
    var result: i64 = 0;
    for (text) |c| {
        if (c >= '0' and c <= '9') {
            result = result * 10 + @as(i64, c - '0');
        }
    }
    return result;
}

/// parsea decimal con formato europeo (8,5 → 8.5)
pub fn parseEuropeanDecimal(text: []const u8) f64 {
    if (std.mem.indexOf(u8, text, ",")) |comma_pos| {
        const int_part = std.fmt.parseFloat(f64, text[0..comma_pos]) catch 0.0;
        const frac_str = text[comma_pos + 1 ..];
        const frac_part = std.fmt.parseFloat(f64, frac_str) catch 0.0;
        const frac_divisor: f64 = @floatFromInt(std.math.pow(u64, 10, frac_str.len));
        return int_part + frac_part / frac_divisor;
    }
    return std.fmt.parseFloat(f64, text) catch 0.0;
}

/// parsea valor de balance (formato completo o abreviado con M)
pub fn parseBalanceValue(text: []const u8) i64 {
    const trimmed = std.mem.trim(u8, text, " \t\n\r");

    // formato abreviado con M (e.g., "255,0M" = 255,000,000)
    if (std.mem.indexOf(u8, trimmed, "M")) |m_pos| {
        const num_part = trimmed[0..m_pos];
        const multiplier: i64 = 1_000_000;

        if (std.mem.indexOf(u8, num_part, ",")) |comma_pos| {
            const int_str = num_part[0..comma_pos];
            const frac_str = num_part[comma_pos + 1 ..];
            const int_part = std.fmt.parseInt(i64, int_str, 10) catch 0;
            const frac_part = std.fmt.parseInt(i64, frac_str, 10) catch 0;
            const frac_len: u6 = @intCast(frac_str.len);
            const frac_divisor: i64 = std.math.pow(i64, 10, frac_len);
            return int_part * multiplier + @divTrunc(frac_part * multiplier, frac_divisor);
        } else {
            const int_part = std.fmt.parseInt(i64, num_part, 10) catch 0;
            return int_part * multiplier;
        }
    }

    return parseEuropeanNumber(trimmed);
}

/// elimina tags HTML de un string
pub fn stripTags(allocator: std.mem.Allocator, html: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{};
    var in_tag = false;

    for (html) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// normaliza espacios en blanco (múltiples espacios → uno solo)
pub fn normalizeWhitespace(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{};
    var last_was_space = true;

    for (text) |c| {
        const is_space = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (is_space) {
            if (!last_was_space) {
                try result.append(allocator, ' ');
                last_was_space = true;
            }
        } else {
            try result.append(allocator, c);
            last_was_space = false;
        }
    }

    var slice = result.items;
    if (slice.len > 0 and slice[slice.len - 1] == ' ') {
        slice = slice[0 .. slice.len - 1];
    }
    if (slice.len > 0 and slice[0] == ' ') {
        slice = slice[1..];
    }

    return try allocator.dupe(u8, slice);
}

test "parseEuropeanNumber" {
    try std.testing.expectEqual(@as(i64, 1234567), parseEuropeanNumber("1.234.567"));
    try std.testing.expectEqual(@as(i64, 100), parseEuropeanNumber("100"));
}

test "parseEuropeanDecimal" {
    try std.testing.expectApproxEqAbs(@as(f64, 8.5), parseEuropeanDecimal("8,5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 12.75), parseEuropeanDecimal("12,75"), 0.001);
}

test "extractBetween" {
    const html = "<div class=\"name\">John</div>";
    const result = extractBetween(html, "class=\"name\">", "</div>");
    try std.testing.expectEqualStrings("John", result.?);
}
