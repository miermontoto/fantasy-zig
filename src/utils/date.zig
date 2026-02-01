const std = @import("std");

/// Parse Spanish relative date string to minutes ago
/// Examples: "hace 5 minutos", "hace 2 horas", "hace 3 días"
pub fn parseRelativeDate(text: []const u8) i64 {
    // Normalize to lowercase for comparison
    var lower_buf: [256]u8 = undefined;
    const lower = std.ascii.lowerString(&lower_buf, text);

    // Check for "hace X segundos"
    if (std.mem.indexOf(u8, lower, "segundo")) |_| {
        const num = extractNumber(lower);
        return @divFloor(num, 60); // Convert seconds to minutes (rounded)
    }

    // Check for "hace X minutos"
    if (std.mem.indexOf(u8, lower, "minuto")) |_| {
        return extractNumber(lower);
    }

    // Check for "hace X horas"
    if (std.mem.indexOf(u8, lower, "hora")) |_| {
        return extractNumber(lower) * 60;
    }

    // Check for "hace X días"
    if (std.mem.indexOf(u8, lower, "día") != null or std.mem.indexOf(u8, lower, "dia") != null) {
        return extractNumber(lower) * 24 * 60;
    }

    // Default: far in the past
    return std.math.maxInt(i64);
}

/// Extract the first number from a string
fn extractNumber(text: []const u8) i64 {
    var num: i64 = 0;
    var found_digit = false;

    for (text) |c| {
        if (c >= '0' and c <= '9') {
            num = num * 10 + @as(i64, c - '0');
            found_digit = true;
        } else if (found_digit) {
            break; // Stop after first number sequence
        }
    }

    return if (num == 0) 1 else num; // Default to 1 if no number found
}

/// Convert minutes ago to a relative time string in Spanish
pub fn formatRelativeTime(allocator: std.mem.Allocator, minutes: i64) ![]const u8 {
    if (minutes < 1) {
        return try allocator.dupe(u8, "hace unos segundos");
    } else if (minutes == 1) {
        return try allocator.dupe(u8, "hace 1 minuto");
    } else if (minutes < 60) {
        return try std.fmt.allocPrint(allocator, "hace {d} minutos", .{minutes});
    } else if (minutes < 120) {
        return try allocator.dupe(u8, "hace 1 hora");
    } else if (minutes < 24 * 60) {
        return try std.fmt.allocPrint(allocator, "hace {d} horas", .{@divFloor(minutes, 60)});
    } else if (minutes < 48 * 60) {
        return try allocator.dupe(u8, "hace 1 día");
    } else {
        return try std.fmt.allocPrint(allocator, "hace {d} días", .{@divFloor(minutes, 24 * 60)});
    }
}

/// Get current timestamp in ISO 8601 format
pub fn getCurrentTimestamp(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds: u64 = @intCast(timestamp);
    const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch_day.getDaySeconds();
    const year_day = epoch_day.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        @intFromEnum(month_day.month) + 1, // Month enum is 0-indexed
        month_day.day_index + 1, // Day is 0-indexed
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

test "parse relative date" {
    try std.testing.expectEqual(@as(i64, 5), parseRelativeDate("hace 5 minutos"));
    try std.testing.expectEqual(@as(i64, 120), parseRelativeDate("hace 2 horas"));
    try std.testing.expectEqual(@as(i64, 4320), parseRelativeDate("hace 3 días"));
    try std.testing.expectEqual(@as(i64, 0), parseRelativeDate("hace 30 segundos"));
}

test "extract number" {
    try std.testing.expectEqual(@as(i64, 5), extractNumber("hace 5 minutos"));
    try std.testing.expectEqual(@as(i64, 12), extractNumber("12 horas"));
    try std.testing.expectEqual(@as(i64, 1), extractNumber("hace unos minutos")); // No number, default to 1
}
