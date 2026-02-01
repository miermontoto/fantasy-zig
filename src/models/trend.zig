const std = @import("std");

pub const Trend = enum {
    up,
    down,
    neutral,

    pub fn fromString(str: ?[]const u8) Trend {
        const s = str orelse return .neutral;
        if (s.len == 0) return .neutral;

        if (std.mem.eql(u8, s, "↑") or std.mem.eql(u8, s, "+")) return .up;
        if (std.mem.eql(u8, s, "↓") or std.mem.eql(u8, s, "-")) return .down;
        return .neutral;
    }

    pub fn fromValue(value: i64) Trend {
        if (value > 0) return .up;
        if (value < 0) return .down;
        return .neutral;
    }

    pub fn toSymbol(self: Trend) []const u8 {
        return switch (self) {
            .up => "↑",
            .down => "↓",
            .neutral => "~",
        };
    }

    pub fn toColor(self: Trend) []const u8 {
        return switch (self) {
            .up => "text-green-500",
            .down => "text-red-500",
            .neutral => "text-yellow-500",
        };
    }

    pub fn isPositive(self: Trend) bool {
        return self == .up;
    }

    pub fn isNegative(self: Trend) bool {
        return self == .down;
    }

    pub fn isNeutral(self: Trend) bool {
        return self == .neutral;
    }

    pub fn jsonStringify(self: Trend, jw: anytype) !void {
        try jw.write(@tagName(self));
    }
};

test "trend from string" {
    try std.testing.expectEqual(Trend.up, Trend.fromString("↑"));
    try std.testing.expectEqual(Trend.down, Trend.fromString("↓"));
    try std.testing.expectEqual(Trend.neutral, Trend.fromString(null));
}

test "trend from value" {
    try std.testing.expectEqual(Trend.up, Trend.fromValue(100));
    try std.testing.expectEqual(Trend.down, Trend.fromValue(-50));
    try std.testing.expectEqual(Trend.neutral, Trend.fromValue(0));
}
