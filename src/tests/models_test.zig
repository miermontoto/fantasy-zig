//! tests para modelos de datos
//! cubre Position, Status, Trend, Player

const std = @import("std");
const Position = @import("../models/position.zig").Position;
const Status = @import("../models/status.zig").Status;
const Trend = @import("../models/trend.zig").Trend;
const Player = @import("../models/player.zig").Player;
const MarketPlayer = @import("../models/player.zig").MarketPlayer;
const TeamPlayer = @import("../models/player.zig").TeamPlayer;
const ValueChange = @import("../models/player.zig").ValueChange;

// ========== Position tests ==========

test "Position.fromString - valid strings" {
    try std.testing.expectEqual(Position.goalkeeper, Position.fromString("1").?);
    try std.testing.expectEqual(Position.defender, Position.fromString("2").?);
    try std.testing.expectEqual(Position.midfielder, Position.fromString("3").?);
    try std.testing.expectEqual(Position.forward, Position.fromString("4").?);
}

test "Position.fromString - position codes" {
    try std.testing.expectEqual(Position.goalkeeper, Position.fromString("PT").?);
    try std.testing.expectEqual(Position.defender, Position.fromString("DF").?);
    try std.testing.expectEqual(Position.midfielder, Position.fromString("MC").?);
    try std.testing.expectEqual(Position.forward, Position.fromString("DL").?);
}

test "Position.fromString - pos prefix" {
    try std.testing.expectEqual(Position.goalkeeper, Position.fromString("pos-1").?);
    try std.testing.expectEqual(Position.defender, Position.fromString("pos-2").?);
}

test "Position.fromString - invalid string" {
    try std.testing.expect(Position.fromString("5") == null);
    try std.testing.expect(Position.fromString("0") == null);
    try std.testing.expect(Position.fromString("abc") == null);
    try std.testing.expect(Position.fromString("") == null);
}

test "Position.toCode" {
    try std.testing.expectEqualStrings("PT", Position.goalkeeper.toCode());
    try std.testing.expectEqualStrings("DF", Position.defender.toCode());
    try std.testing.expectEqualStrings("MC", Position.midfielder.toCode());
    try std.testing.expectEqualStrings("DL", Position.forward.toCode());
}

test "Position.toFullName" {
    try std.testing.expectEqualStrings("Portero", Position.goalkeeper.toFullName());
    try std.testing.expectEqualStrings("Defensa", Position.defender.toFullName());
    try std.testing.expectEqualStrings("Mediocampista", Position.midfielder.toFullName());
    try std.testing.expectEqualStrings("Delantero", Position.forward.toFullName());
}

// ========== Status tests ==========

test "Status.fromString - valid strings" {
    try std.testing.expectEqual(Status.injury, Status.fromString("injury"));
    try std.testing.expectEqual(Status.doubt, Status.fromString("doubt"));
    try std.testing.expectEqual(Status.red, Status.fromString("red"));
    try std.testing.expectEqual(Status.five, Status.fromString("five"));
}

test "Status.fromString - invalid returns none" {
    try std.testing.expectEqual(Status.none, Status.fromString("unknown"));
    try std.testing.expectEqual(Status.none, Status.fromString(null));
    try std.testing.expectEqual(Status.none, Status.fromString(""));
}

test "Status.toSymbol" {
    try std.testing.expectEqualStrings("", Status.none.toSymbol());
    try std.testing.expectEqualStrings("+", Status.injury.toSymbol());
    try std.testing.expectEqualStrings("?", Status.doubt.toSymbol());
    try std.testing.expectEqualStrings("X", Status.red.toSymbol());
    try std.testing.expectEqualStrings("5", Status.five.toSymbol());
}

test "Status.isPresent" {
    try std.testing.expect(!Status.none.isPresent());
    try std.testing.expect(Status.injury.isPresent());
    try std.testing.expect(Status.doubt.isPresent());
}

// ========== Trend tests ==========

test "Trend.fromString - arrows" {
    try std.testing.expectEqual(Trend.up, Trend.fromString("↑"));
    try std.testing.expectEqual(Trend.down, Trend.fromString("↓"));
    try std.testing.expectEqual(Trend.up, Trend.fromString("+"));
    try std.testing.expectEqual(Trend.down, Trend.fromString("-"));
}

test "Trend.fromString - invalid returns neutral" {
    try std.testing.expectEqual(Trend.neutral, Trend.fromString("invalid"));
    try std.testing.expectEqual(Trend.neutral, Trend.fromString(null));
    try std.testing.expectEqual(Trend.neutral, Trend.fromString(""));
}

test "Trend.fromValue - positive" {
    try std.testing.expectEqual(Trend.up, Trend.fromValue(100));
    try std.testing.expectEqual(Trend.up, Trend.fromValue(1));
}

test "Trend.fromValue - negative" {
    try std.testing.expectEqual(Trend.down, Trend.fromValue(-100));
    try std.testing.expectEqual(Trend.down, Trend.fromValue(-1));
}

test "Trend.fromValue - zero" {
    try std.testing.expectEqual(Trend.neutral, Trend.fromValue(0));
}

test "Trend.toSymbol" {
    try std.testing.expectEqualStrings("↑", Trend.up.toSymbol());
    try std.testing.expectEqualStrings("↓", Trend.down.toSymbol());
    try std.testing.expectEqualStrings("~", Trend.neutral.toSymbol());
}

test "Trend predicates" {
    try std.testing.expect(Trend.up.isPositive());
    try std.testing.expect(!Trend.up.isNegative());
    try std.testing.expect(Trend.down.isNegative());
    try std.testing.expect(!Trend.down.isPositive());
    try std.testing.expect(Trend.neutral.isNeutral());
}

// ========== Player tests ==========

test "Player.ppm - calculation" {
    const player = Player{
        .name = "Test",
        .position = .forward,
        .points = 100,
        .value = 10_000_000,
        .average = 5.0,
    };

    const ppm = player.ppm();
    // 100 / 10_000_000 * 1_000_000 = 10.0
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), ppm, 0.001);
}

test "Player.ppm - zero value returns zero" {
    const player = Player{
        .name = "Test",
        .position = .forward,
        .points = 100,
        .value = 0,
    };

    const ppm = player.ppm();
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ppm, 0.001);
}

test "Player.ppm - zero points returns zero" {
    const player = Player{
        .name = "Test",
        .position = .forward,
        .points = 0,
        .value = 10_000_000,
    };

    const ppm = player.ppm();
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ppm, 0.001);
}

test "Player.streakSum - calculation" {
    const streak_data = [_]i32{ 5, 6, 4, 3, 2 };
    const player = Player{
        .name = "Test",
        .streak = &streak_data,
    };

    const sum = player.streakSum();
    try std.testing.expectEqual(@as(i32, 20), sum);
}

test "Player.streakSum - empty streak" {
    const player = Player{
        .name = "Test",
    };

    const sum = player.streakSum();
    try std.testing.expectEqual(@as(i32, 0), sum);
}

test "Player.gpm - calculation" {
    const player = Player{
        .name = "Test",
        .goals = 5,
        .matches = 10,
    };

    const gpm = player.gpm();
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), gpm.?, 0.001);
}

test "Player.gpm - null values" {
    const player = Player{
        .name = "Test",
    };

    try std.testing.expect(player.gpm() == null);
}

// ========== MarketPlayer tests ==========

test "MarketPlayer.overprice - positive percentage" {
    const player = MarketPlayer{
        .base = .{
            .name = "Test",
            .value = 10_000_000,
        },
        .asked_price = 12_000_000,
    };

    const overprice = player.overprice();
    // (12M - 10M) / 10M * 100 = 20%
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), overprice.?, 0.01);
}

test "MarketPlayer.overprice - negative (discount)" {
    const player = MarketPlayer{
        .base = .{
            .name = "Test",
            .value = 10_000_000,
        },
        .asked_price = 8_000_000,
    };

    const overprice = player.overprice();
    // (8M - 10M) / 10M * 100 = -20%
    try std.testing.expectApproxEqAbs(@as(f64, -20.0), overprice.?, 0.01);
}

test "MarketPlayer.overprice - zero value returns null" {
    const player = MarketPlayer{
        .base = .{
            .name = "Test",
            .value = 0,
        },
        .asked_price = 1_000_000,
    };

    try std.testing.expect(player.overprice() == null);
}

test "MarketPlayer.isFree" {
    const free_player = MarketPlayer{
        .base = .{ .name = "Free" },
        .offered_by = "Libre",
    };
    try std.testing.expect(free_player.isFree());

    const owned_player = MarketPlayer{
        .base = .{ .name = "Owned" },
        .offered_by = "Some Owner",
    };
    try std.testing.expect(!owned_player.isFree());
}

// ========== TeamPlayer tests ==========

test "TeamPlayer - default values" {
    const player = TeamPlayer{
        .base = .{ .name = "Bench" },
    };

    try std.testing.expect(!player.selected);
    try std.testing.expect(!player.being_sold);
    try std.testing.expect(player.own);
}

// ========== ValueChange tests ==========

test "ValueChange.Timespan.fromSpanish - valid strings" {
    try std.testing.expectEqual(ValueChange.Timespan.day, ValueChange.Timespan.fromSpanish("Hoy (día)").?);
    try std.testing.expectEqual(ValueChange.Timespan.week, ValueChange.Timespan.fromSpanish("Última semana").?);
    try std.testing.expectEqual(ValueChange.Timespan.month, ValueChange.Timespan.fromSpanish("Último mes").?);
    try std.testing.expectEqual(ValueChange.Timespan.year, ValueChange.Timespan.fromSpanish("Último año").?);
}

test "ValueChange.Timespan.fromSpanish - partial match" {
    try std.testing.expectEqual(ValueChange.Timespan.day, ValueChange.Timespan.fromSpanish("día de hoy").?);
    try std.testing.expectEqual(ValueChange.Timespan.week, ValueChange.Timespan.fromSpanish("esta semana").?);
}

test "ValueChange.Timespan.fromSpanish - invalid string" {
    try std.testing.expect(ValueChange.Timespan.fromSpanish("invalid") == null);
    try std.testing.expect(ValueChange.Timespan.fromSpanish("") == null);
}

// ========== OfferPlayer tests ==========

test "OfferPlayer.difference" {
    const player = @import("../models/player.zig").OfferPlayer{
        .base = .{
            .name = "Test",
            .value = 10_000_000,
        },
        .best_bid = 12_000_000,
    };

    try std.testing.expectEqual(@as(i64, 2_000_000), player.difference());
}

test "OfferPlayer.differencePercent" {
    const player = @import("../models/player.zig").OfferPlayer{
        .base = .{
            .name = "Test",
            .value = 10_000_000,
        },
        .best_bid = 12_000_000,
    };

    // (12M / 10M - 1) * 100 = 20%
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), player.differencePercent(), 0.01);
}
