const std = @import("std");

pub const Status = enum {
    none,
    injury,
    doubt,
    red,
    five,

    pub fn fromString(str: ?[]const u8) Status {
        const s = str orelse return .none;
        if (s.len == 0) return .none;

        if (std.mem.eql(u8, s, "injury")) return .injury;
        if (std.mem.eql(u8, s, "doubt")) return .doubt;
        if (std.mem.eql(u8, s, "red")) return .red;
        if (std.mem.eql(u8, s, "five")) return .five;
        return .none;
    }

    pub fn toSymbol(self: Status) []const u8 {
        return switch (self) {
            .none => "",
            .injury => "+",
            .doubt => "?",
            .red => "X",
            .five => "5",
        };
    }

    pub fn toColor(self: Status) []const u8 {
        return switch (self) {
            .none => "",
            .injury => "bg-red-500",
            .doubt => "bg-yellow-500",
            .red => "bg-red-500",
            .five => "bg-yellow-500",
        };
    }

    pub fn isPresent(self: Status) bool {
        return self != .none;
    }

    pub fn jsonStringify(self: Status, jw: anytype) !void {
        if (self == .none) {
            try jw.write(null);
        } else {
            try jw.write(@tagName(self));
        }
    }
};

test "status from string" {
    try std.testing.expectEqual(Status.injury, Status.fromString("injury"));
    try std.testing.expectEqual(Status.none, Status.fromString(null));
    try std.testing.expectEqual(Status.none, Status.fromString(""));
}
