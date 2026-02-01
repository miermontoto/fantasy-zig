const std = @import("std");

pub const Position = enum(u8) {
    goalkeeper = 1, // PT - Portero
    defender = 2, // DF - Defensa
    midfielder = 3, // MC - Mediocampista
    forward = 4, // DL - Delantero

    pub fn fromString(str: []const u8) ?Position {
        if (std.mem.eql(u8, str, "pos-1") or std.mem.eql(u8, str, "1") or std.mem.eql(u8, str, "PT")) {
            return .goalkeeper;
        } else if (std.mem.eql(u8, str, "pos-2") or std.mem.eql(u8, str, "2") or std.mem.eql(u8, str, "DF")) {
            return .defender;
        } else if (std.mem.eql(u8, str, "pos-3") or std.mem.eql(u8, str, "3") or std.mem.eql(u8, str, "MC")) {
            return .midfielder;
        } else if (std.mem.eql(u8, str, "pos-4") or std.mem.eql(u8, str, "4") or std.mem.eql(u8, str, "DL")) {
            return .forward;
        }
        return null;
    }

    pub fn toCode(self: Position) []const u8 {
        return switch (self) {
            .goalkeeper => "PT",
            .defender => "DF",
            .midfielder => "MC",
            .forward => "DL",
        };
    }

    pub fn toFullName(self: Position) []const u8 {
        return switch (self) {
            .goalkeeper => "Portero",
            .defender => "Defensa",
            .midfielder => "Mediocampista",
            .forward => "Delantero",
        };
    }

    pub fn toColor(self: Position) []const u8 {
        return switch (self) {
            .goalkeeper => "bg-yellow-300",
            .defender => "bg-cyan-400",
            .midfielder => "bg-green-400",
            .forward => "bg-red-400",
        };
    }

    pub fn jsonStringify(self: Position, jw: anytype) !void {
        try jw.write(self.toCode());
    }
};

test "position from string" {
    const pos1 = Position.fromString("pos-1");
    try std.testing.expectEqual(Position.goalkeeper, pos1.?);

    const pos2 = Position.fromString("DF");
    try std.testing.expectEqual(Position.defender, pos2.?);

    const pos3 = Position.fromString("3");
    try std.testing.expectEqual(Position.midfielder, pos3.?);
}
