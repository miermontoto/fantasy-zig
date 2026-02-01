const std = @import("std");

/// Format a number with European style thousands separator (1.000.000)
pub fn formatNumber(allocator: std.mem.Allocator, num: i64) ![]const u8 {
    if (num == 0) return try allocator.dupe(u8, "0");

    const is_negative = num < 0;
    var abs_num: u64 = if (is_negative) @intCast(-num) else @intCast(num);

    var digits = std.ArrayList(u8).init(allocator);
    defer digits.deinit();

    var count: usize = 0;
    while (abs_num > 0) {
        if (count > 0 and count % 3 == 0) {
            try digits.append('.');
        }
        try digits.append(@intCast('0' + @as(u8, @intCast(abs_num % 10))));
        abs_num /= 10;
        count += 1;
    }

    if (is_negative) {
        try digits.append('-');
    }

    // Reverse the result
    var result = try allocator.alloc(u8, digits.items.len);
    for (digits.items, 0..) |c, i| {
        result[digits.items.len - 1 - i] = c;
    }

    return result;
}

/// Format a value as currency (€ 1.000.000)
pub fn formatValue(allocator: std.mem.Allocator, num: i64) ![]const u8 {
    const formatted = try formatNumber(allocator, num);
    defer allocator.free(formatted);
    return try std.fmt.allocPrint(allocator, "€ {s}", .{formatted});
}

/// Parse a number from European format string
pub fn parseEuropeanNumber(text: []const u8) i64 {
    var result: i64 = 0;
    var is_negative = false;

    for (text) |c| {
        if (c == '-') {
            is_negative = true;
        } else if (c >= '0' and c <= '9') {
            result = result * 10 + @as(i64, c - '0');
        }
    }

    return if (is_negative) -result else result;
}

/// Format a float with specified decimal places
pub fn formatFloat(allocator: std.mem.Allocator, num: f64, decimals: u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{d:.{d}}", .{ num, decimals });
}

test "format number" {
    const allocator = std.testing.allocator;

    const result1 = try formatNumber(allocator, 1000000);
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("1.000.000", result1);

    const result2 = try formatNumber(allocator, -5000);
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("-5.000", result2);

    const result3 = try formatNumber(allocator, 0);
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("0", result3);
}

test "parse european number" {
    try std.testing.expectEqual(@as(i64, 1000000), parseEuropeanNumber("1.000.000"));
    try std.testing.expectEqual(@as(i64, -5000), parseEuropeanNumber("-5.000"));
    try std.testing.expectEqual(@as(i64, 123), parseEuropeanNumber("123"));
}
