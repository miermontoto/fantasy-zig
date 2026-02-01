const std = @import("std");

/// crea un comparador genérico para ordenar slices de structs por un campo específico
/// T: tipo del struct
/// field: nombre del campo a comparar (comptime string)
/// asc: true para ascendente, false para descendente
pub fn byField(comptime T: type, comptime field: []const u8, comptime asc: bool) fn (void, T, T) bool {
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            const a_val = @field(a, field);
            const b_val = @field(b, field);
            return if (asc) a_val < b_val else a_val > b_val;
        }
    }.compare;
}

/// crea un comparador para campos anidados (e.g., "base.points")
/// útil para tipos como MarketPlayer donde el campo está en base: Player
pub fn byNestedField(
    comptime T: type,
    comptime outer_field: []const u8,
    comptime inner_field: []const u8,
    comptime asc: bool,
) fn (void, T, T) bool {
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            const a_outer = @field(a, outer_field);
            const b_outer = @field(b, outer_field);
            const a_val = @field(a_outer, inner_field);
            const b_val = @field(b_outer, inner_field);
            return if (asc) a_val < b_val else a_val > b_val;
        }
    }.compare;
}

/// ordena un slice de MarketPlayer por un campo específico con dirección runtime
/// soporta campos: "points", "value", "price", "average"
pub fn sortMarketPlayers(
    comptime MarketPlayer: type,
    slice: []MarketPlayer,
    field: []const u8,
    ascending: bool,
) void {
    if (std.mem.eql(u8, field, "points")) {
        if (ascending) {
            std.mem.sort(MarketPlayer, slice, {}, byNestedField(MarketPlayer, "base", "points", true));
        } else {
            std.mem.sort(MarketPlayer, slice, {}, byNestedField(MarketPlayer, "base", "points", false));
        }
    } else if (std.mem.eql(u8, field, "value")) {
        if (ascending) {
            std.mem.sort(MarketPlayer, slice, {}, byNestedField(MarketPlayer, "base", "value", true));
        } else {
            std.mem.sort(MarketPlayer, slice, {}, byNestedField(MarketPlayer, "base", "value", false));
        }
    } else if (std.mem.eql(u8, field, "price")) {
        if (ascending) {
            std.mem.sort(MarketPlayer, slice, {}, byField(MarketPlayer, "asked_price", true));
        } else {
            std.mem.sort(MarketPlayer, slice, {}, byField(MarketPlayer, "asked_price", false));
        }
    } else if (std.mem.eql(u8, field, "average")) {
        if (ascending) {
            std.mem.sort(MarketPlayer, slice, {}, byNestedField(MarketPlayer, "base", "average", true));
        } else {
            std.mem.sort(MarketPlayer, slice, {}, byNestedField(MarketPlayer, "base", "average", false));
        }
    }
}

test "byField sorts integers ascending" {
    const Item = struct { value: i32, name: []const u8 };
    var items = [_]Item{
        .{ .value = 3, .name = "c" },
        .{ .value = 1, .name = "a" },
        .{ .value = 2, .name = "b" },
    };

    std.mem.sort(Item, &items, {}, byField(Item, "value", true));

    try std.testing.expectEqual(@as(i32, 1), items[0].value);
    try std.testing.expectEqual(@as(i32, 2), items[1].value);
    try std.testing.expectEqual(@as(i32, 3), items[2].value);
}

test "byField sorts integers descending" {
    const Item = struct { value: i32, name: []const u8 };
    var items = [_]Item{
        .{ .value = 1, .name = "a" },
        .{ .value = 3, .name = "c" },
        .{ .value = 2, .name = "b" },
    };

    std.mem.sort(Item, &items, {}, byField(Item, "value", false));

    try std.testing.expectEqual(@as(i32, 3), items[0].value);
    try std.testing.expectEqual(@as(i32, 2), items[1].value);
    try std.testing.expectEqual(@as(i32, 1), items[2].value);
}

test "byNestedField sorts nested structs" {
    const Inner = struct { score: i32 };
    const Outer = struct { inner: Inner, id: u8 };

    var items = [_]Outer{
        .{ .inner = .{ .score = 30 }, .id = 1 },
        .{ .inner = .{ .score = 10 }, .id = 2 },
        .{ .inner = .{ .score = 20 }, .id = 3 },
    };

    std.mem.sort(Outer, &items, {}, byNestedField(Outer, "inner", "score", true));

    try std.testing.expectEqual(@as(u8, 2), items[0].id);
    try std.testing.expectEqual(@as(u8, 3), items[1].id);
    try std.testing.expectEqual(@as(u8, 1), items[2].id);
}
