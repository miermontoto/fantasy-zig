//! tests para el sistema de rating de jugadores

const std = @import("std");
const RatingService = @import("../services/rating.zig").RatingService;
const PlayerStats = @import("../services/rating.zig").PlayerStats;
const RatingTier = @import("../services/rating.zig").RatingTier;

// ========== Rating Tier tests ==========

test "RatingTier - elite threshold" {
    try std.testing.expectEqual(RatingTier.elite, RatingTier.fromScore(90));
    try std.testing.expectEqual(RatingTier.elite, RatingTier.fromScore(95));
    try std.testing.expectEqual(RatingTier.elite, RatingTier.fromScore(100));
}

test "RatingTier - excellent threshold" {
    try std.testing.expectEqual(RatingTier.excellent, RatingTier.fromScore(80));
    try std.testing.expectEqual(RatingTier.excellent, RatingTier.fromScore(85));
    try std.testing.expectEqual(RatingTier.excellent, RatingTier.fromScore(89.9));
}

test "RatingTier - good threshold" {
    try std.testing.expectEqual(RatingTier.good, RatingTier.fromScore(70));
    try std.testing.expectEqual(RatingTier.good, RatingTier.fromScore(75));
    try std.testing.expectEqual(RatingTier.good, RatingTier.fromScore(79.9));
}

test "RatingTier - average threshold" {
    try std.testing.expectEqual(RatingTier.average, RatingTier.fromScore(55));
    try std.testing.expectEqual(RatingTier.average, RatingTier.fromScore(60));
    try std.testing.expectEqual(RatingTier.average, RatingTier.fromScore(69.9));
}

test "RatingTier - below_average threshold" {
    try std.testing.expectEqual(RatingTier.below_average, RatingTier.fromScore(40));
    try std.testing.expectEqual(RatingTier.below_average, RatingTier.fromScore(50));
    try std.testing.expectEqual(RatingTier.below_average, RatingTier.fromScore(54.9));
}

test "RatingTier - poor threshold" {
    try std.testing.expectEqual(RatingTier.poor, RatingTier.fromScore(0));
    try std.testing.expectEqual(RatingTier.poor, RatingTier.fromScore(20));
    try std.testing.expectEqual(RatingTier.poor, RatingTier.fromScore(39.9));
}

test "RatingTier - toString" {
    try std.testing.expectEqualStrings("Elite", RatingTier.elite.toString());
    try std.testing.expectEqualStrings("Excellent", RatingTier.excellent.toString());
    try std.testing.expectEqualStrings("Good", RatingTier.good.toString());
    try std.testing.expectEqualStrings("Average", RatingTier.average.toString());
    try std.testing.expectEqualStrings("Below Average", RatingTier.below_average.toString());
    try std.testing.expectEqualStrings("Poor", RatingTier.poor.toString());
}

// ========== Rating calculation tests ==========

test "rating - high ppm player has high efficiency" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 5_000_000,
        .points = 100,
        .average = 5.0,
        .ppm = 20.0, // excelente eficiencia
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.efficiency >= 90);
}

test "rating - low ppm player has low efficiency" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 50_000_000,
        .points = 100,
        .average = 5.0,
        .ppm = 2.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.efficiency < 50);
}

test "rating - high participation rate scores well" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 10_000_000,
        .points = 80,
        .average = 5.0,
        .participation_rate = 95.0,
        .ppm = 8.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.participation >= 90);
}

test "rating - low participation rate scores poorly" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 10_000_000,
        .points = 80,
        .average = 5.0,
        .participation_rate = 30.0,
        .ppm = 8.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.participation < 50);
}

test "rating - hot streak boosts form" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 10_000_000,
        .points = 80,
        .average = 5.0,
        .streak_sum = 45, // muy buena racha
        .ppm = 8.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.form >= 80);
}

test "rating - cold streak hurts form" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 10_000_000,
        .points = 80,
        .average = 5.0,
        .streak_sum = 5, // muy mala racha
        .ppm = 8.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.form < 30);
}

// ========== Edge Cases ==========

test "rating - zero values" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 0,
        .points = 0,
        .average = 0,
        .streak_sum = 0,
        .participation_rate = 0,
        .clauses_rank = null,
        .clause = null,
        .ppm = 0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.overall >= 0);
    try std.testing.expect(rating.overall <= 100);
}

test "rating - null optional values" {
    var service = RatingService.init(null);

    const stats = PlayerStats{
        .value = 5_000_000,
        .points = 50,
        .average = 4.0,
        .streak_sum = 15,
        .participation_rate = null,
        .clauses_rank = null,
        .clause = null,
        .ppm = 10.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.overall >= 0);
    try std.testing.expect(rating.overall <= 100);
}

test "rating - overall score is bounded" {
    var service = RatingService.init(null);

    // jugador con stats muy altos
    const stats = PlayerStats{
        .value = 100_000_000,
        .points = 300,
        .average = 9.0,
        .streak_sum = 50,
        .participation_rate = 100.0,
        .clauses_rank = 1,
        .clause = 100_000_000,
        .ppm = 3.0,
    };

    const rating = service.calculateRating(stats);

    try std.testing.expect(rating.overall >= 0);
    try std.testing.expect(rating.overall <= 100);
}
