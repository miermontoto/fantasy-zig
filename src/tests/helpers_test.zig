//! tests para funciones auxiliares de parsing
//! cubre casos edge y escenarios comunes de scraping

const std = @import("std");
const helpers = @import("../services/scraper/helpers.zig");

// ========== extractBetween tests ==========

test "extractBetween - basic extraction" {
    const html = "<div class=\"name\">John Doe</div>";
    const result = helpers.extractBetween(html, "class=\"name\">", "</div>");
    try std.testing.expectEqualStrings("John Doe", result.?);
}

test "extractBetween - nested tags" {
    const html = "<span class=\"points\"><b>123</b></span>";
    const result = helpers.extractBetween(html, "class=\"points\">", "</span>");
    try std.testing.expectEqualStrings("<b>123</b>", result.?);
}

test "extractBetween - not found start marker" {
    const html = "<div>content</div>";
    const result = helpers.extractBetween(html, "class=\"missing\">", "</div>");
    try std.testing.expect(result == null);
}

test "extractBetween - not found end marker" {
    const html = "<div class=\"name\">John";
    const result = helpers.extractBetween(html, "class=\"name\">", "</div>");
    try std.testing.expect(result == null);
}

test "extractBetween - empty content" {
    const html = "<div class=\"empty\"></div>";
    const result = helpers.extractBetween(html, "class=\"empty\">", "</div>");
    try std.testing.expectEqualStrings("", result.?);
}

test "extractBetween - multiple matches returns first" {
    const html = "<div class=\"x\">first</div><div class=\"x\">second</div>";
    const result = helpers.extractBetween(html, "class=\"x\">", "</div>");
    try std.testing.expectEqualStrings("first", result.?);
}

// ========== extractAttribute tests ==========

test "extractAttribute - basic attribute" {
    const html = "<div data-id=\"12345\" class=\"player\">";
    const result = helpers.extractAttribute(html, "data-id");
    try std.testing.expectEqualStrings("12345", result.?);
}

test "extractAttribute - attribute not found" {
    const html = "<div class=\"player\">";
    const result = helpers.extractAttribute(html, "data-id");
    try std.testing.expect(result == null);
}

test "extractAttribute - empty attribute value" {
    const html = "<div data-id=\"\" class=\"player\">";
    const result = helpers.extractAttribute(html, "data-id");
    try std.testing.expectEqualStrings("", result.?);
}

test "extractAttribute - attribute with special chars" {
    const html = "<div data-url=\"/player/123?foo=bar\" class=\"x\">";
    const result = helpers.extractAttribute(html, "data-url");
    try std.testing.expectEqualStrings("/player/123?foo=bar", result.?);
}

// ========== parseEuropeanNumber tests ==========

test "parseEuropeanNumber - millions" {
    try std.testing.expectEqual(@as(i64, 12345678), helpers.parseEuropeanNumber("12.345.678"));
}

test "parseEuropeanNumber - thousands" {
    try std.testing.expectEqual(@as(i64, 1234), helpers.parseEuropeanNumber("1.234"));
}

test "parseEuropeanNumber - no separators" {
    try std.testing.expectEqual(@as(i64, 500), helpers.parseEuropeanNumber("500"));
}

test "parseEuropeanNumber - with currency symbol" {
    try std.testing.expectEqual(@as(i64, 1000000), helpers.parseEuropeanNumber("€ 1.000.000"));
}

test "parseEuropeanNumber - empty string" {
    try std.testing.expectEqual(@as(i64, 0), helpers.parseEuropeanNumber(""));
}

test "parseEuropeanNumber - only text" {
    try std.testing.expectEqual(@as(i64, 0), helpers.parseEuropeanNumber("abc"));
}

test "parseEuropeanNumber - mixed text and numbers" {
    try std.testing.expectEqual(@as(i64, 123), helpers.parseEuropeanNumber("abc123def"));
}

// ========== parseEuropeanDecimal tests ==========

test "parseEuropeanDecimal - simple decimal" {
    try std.testing.expectApproxEqAbs(@as(f64, 8.5), helpers.parseEuropeanDecimal("8,5"), 0.001);
}

test "parseEuropeanDecimal - two decimal places" {
    try std.testing.expectApproxEqAbs(@as(f64, 12.75), helpers.parseEuropeanDecimal("12,75"), 0.001);
}

test "parseEuropeanDecimal - integer only" {
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), helpers.parseEuropeanDecimal("10"), 0.001);
}

test "parseEuropeanDecimal - zero" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), helpers.parseEuropeanDecimal("0"), 0.001);
}

// nota: parseEuropeanDecimal maneja negativos parseando solo la parte después del signo

// ========== parseBalanceValue tests ==========

test "parseBalanceValue - millions abbreviated" {
    try std.testing.expectEqual(@as(i64, 255_000_000), helpers.parseBalanceValue("255M"));
}

test "parseBalanceValue - millions with decimal" {
    try std.testing.expectEqual(@as(i64, 255_500_000), helpers.parseBalanceValue("255,5M"));
}

test "parseBalanceValue - millions with two decimals" {
    try std.testing.expectEqual(@as(i64, 12_340_000), helpers.parseBalanceValue("12,34M"));
}

test "parseBalanceValue - full format european" {
    try std.testing.expectEqual(@as(i64, 123456789), helpers.parseBalanceValue("123.456.789"));
}

test "parseBalanceValue - with whitespace" {
    try std.testing.expectEqual(@as(i64, 100_000_000), helpers.parseBalanceValue("  100M  "));
}

test "parseBalanceValue - zero" {
    try std.testing.expectEqual(@as(i64, 0), helpers.parseBalanceValue("0M"));
}

// ========== stripTags tests ==========

test "stripTags - simple tag" {
    const allocator = std.testing.allocator;
    const result = try helpers.stripTags(allocator, "<b>bold</b>");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("bold", result);
}

test "stripTags - multiple tags" {
    const allocator = std.testing.allocator;
    const result = try helpers.stripTags(allocator, "<div><span>hello</span> <b>world</b></div>");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "stripTags - no tags" {
    const allocator = std.testing.allocator;
    const result = try helpers.stripTags(allocator, "plain text");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("plain text", result);
}

test "stripTags - empty string" {
    const allocator = std.testing.allocator;
    const result = try helpers.stripTags(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "stripTags - self-closing tags" {
    const allocator = std.testing.allocator;
    const result = try helpers.stripTags(allocator, "line1<br/>line2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("line1line2", result);
}

// ========== normalizeWhitespace tests ==========

test "normalizeWhitespace - multiple spaces" {
    const allocator = std.testing.allocator;
    const result = try helpers.normalizeWhitespace(allocator, "hello    world");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "normalizeWhitespace - tabs and newlines" {
    const allocator = std.testing.allocator;
    const result = try helpers.normalizeWhitespace(allocator, "hello\t\n\r  world");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "normalizeWhitespace - leading and trailing" {
    const allocator = std.testing.allocator;
    const result = try helpers.normalizeWhitespace(allocator, "   hello world   ");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "normalizeWhitespace - already normalized" {
    const allocator = std.testing.allocator;
    const result = try helpers.normalizeWhitespace(allocator, "hello world");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "normalizeWhitespace - only whitespace" {
    const allocator = std.testing.allocator;
    const result = try helpers.normalizeWhitespace(allocator, "   \t\n   ");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}
