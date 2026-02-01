//! tests para parsing de respuestas HTML (páginas de Fantasy Marca)

const std = @import("std");
const html = @import("../services/scraper/html.zig");

// ========== parseFeedInfo tests ==========

test "parseFeedInfo - complete feed header" {
    const sample_html =
        \\<div class="feed-top-community">
        \\  <span>Liga Premium</span>
        \\</div>
        \\<span class="balance-real-current ">125,5M</span>
        \\<span class="credits-count ">3</span>
        \\<div class="gameweek__name">Jornada 25</div>
        \\<div class="gameweek__status">En curso</div>
    ;

    const info = html.parseFeedInfo(sample_html);

    try std.testing.expectEqualStrings("Liga Premium", info.community);
    try std.testing.expectEqualStrings("125,5M", info.balance);
    try std.testing.expectEqualStrings("3", info.credits);
    try std.testing.expectEqualStrings("Jornada 25", info.gameweek);
    try std.testing.expectEqualStrings("En curso", info.status);
}

test "parseFeedInfo - partial info" {
    const sample_html =
        \\<div class="feed-top-community">
        \\  <span>Mi Liga</span>
        \\</div>
        \\<span class="balance-real-current">50M</span>
    ;

    const info = html.parseFeedInfo(sample_html);

    try std.testing.expectEqualStrings("Mi Liga", info.community);
    try std.testing.expectEqualStrings("50M", info.balance);
    try std.testing.expectEqualStrings("", info.credits);
}

test "parseFeedInfo - empty html" {
    const info = html.parseFeedInfo("");

    try std.testing.expectEqualStrings("", info.community);
    try std.testing.expectEqualStrings("", info.balance);
}

// ========== parseBalanceInfo tests ==========

test "parseBalanceInfo - all values" {
    const sample_html =
        \\<span class="balance-real-current ">100,5M</span>
        \\<span class="balance-real-future ">85,0M</span>
        \\<span class="balance-real-maxdebt ">-20,0M</span>
    ;

    const info = html.parseBalanceInfo(sample_html);

    try std.testing.expectEqual(@as(i64, 100_500_000), info.current_balance);
    try std.testing.expectEqual(@as(i64, 85_000_000), info.future_balance);
    // max_debt se parsea con signo negativo desde el HTML
    try std.testing.expectEqual(@as(i64, -20_000_000), info.max_debt);
}

test "parseBalanceInfo - no space variant" {
    const sample_html =
        \\<span class="balance-real-current">75M</span>
        \\<span class="balance-real-future">60M</span>
    ;

    const info = html.parseBalanceInfo(sample_html);

    try std.testing.expectEqual(@as(i64, 75_000_000), info.current_balance);
    try std.testing.expectEqual(@as(i64, 60_000_000), info.future_balance);
}

test "parseBalanceInfo - empty returns zeros" {
    const info = html.parseBalanceInfo("");

    try std.testing.expectEqual(@as(i64, 0), info.current_balance);
    try std.testing.expectEqual(@as(i64, 0), info.future_balance);
    try std.testing.expectEqual(@as(i64, 0), info.max_debt);
}

// ========== parseFeedMarket tests ==========

test "parseFeedMarket - no card-market section" {
    const allocator = std.testing.allocator;
    const sample_html = "<div>No market content</div>";

    const players = try html.parseFeedMarket(allocator, sample_html);

    try std.testing.expectEqual(@as(usize, 0), players.len);
}

test "parseFeedMarket - empty market" {
    const allocator = std.testing.allocator;
    const sample_html =
        \\<ul class="card-market_unified">
        \\</ul>
    ;

    const players = try html.parseFeedMarket(allocator, sample_html);

    try std.testing.expectEqual(@as(usize, 0), players.len);
}
