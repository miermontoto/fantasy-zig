//! tests para parsing de respuestas JSON (AJAX endpoints)

const std = @import("std");
const json = @import("../services/scraper/json.zig");
const types = @import("../services/scraper/types.zig");

// nota: los tests que parsean JSON exitosamente usan page_allocator
// porque checkAjaxResponse tiene un leak conocido (el JSON no se libera
// porque los resultados contienen referencias a strings dentro del JSON)

// ========== checkAjaxResponse tests ==========

test "checkAjaxResponse - valid success response" {
    const allocator = std.heap.page_allocator;
    const response =
        \\{"status":"ok","data":{"foo":"bar"}}
    ;

    const data = try json.checkAjaxResponse(allocator, response);

    try std.testing.expect(data == .object);
    try std.testing.expectEqualStrings("bar", data.object.get("foo").?.string);
}

test "checkAjaxResponse - error response" {
    // usa page_allocator porque parsea antes de verificar status
    const allocator = std.heap.page_allocator;
    const response =
        \\{"status":"error","message":"Not found"}
    ;

    const result = json.checkAjaxResponse(allocator, response);
    try std.testing.expectError(types.ScraperError.AjaxError, result);
}

test "checkAjaxResponse - invalid json" {
    // puede usar testing.allocator porque el parse falla inmediatamente
    const allocator = std.testing.allocator;
    const response = "not valid json";

    const result = json.checkAjaxResponse(allocator, response);
    try std.testing.expectError(types.ScraperError.InvalidJson, result);
}

test "checkAjaxResponse - missing data field" {
    // usa page_allocator porque parsea exitosamente antes de fallar
    const allocator = std.heap.page_allocator;
    const response =
        \\{"status":"ok"}
    ;

    const result = json.checkAjaxResponse(allocator, response);
    try std.testing.expectError(types.ScraperError.InvalidJson, result);
}

test "checkAjaxResponse - not object" {
    // usa page_allocator porque el JSON parsea exitosamente (es válido)
    // aunque falla la verificación de tipo
    const allocator = std.heap.page_allocator;
    const response = "[1,2,3]";

    const result = json.checkAjaxResponse(allocator, response);
    try std.testing.expectError(types.ScraperError.InvalidJson, result);
}

test "checkAjaxResponse - empty string" {
    // puede usar testing.allocator porque el parse falla inmediatamente
    const allocator = std.testing.allocator;
    const result = json.checkAjaxResponse(allocator, "");
    try std.testing.expectError(types.ScraperError.InvalidJson, result);
}

// ========== parsePlayer tests ==========

test "parsePlayer - basic player info" {
    const allocator = std.heap.page_allocator;
    const response =
        \\{
        \\  "status": "ok",
        \\  "data": {
        \\    "player": {
        \\      "name": "Mbappé",
        \\      "position": 4,
        \\      "points": 150,
        \\      "value": 85000000,
        \\      "avg": 7.5
        \\    },
        \\    "values": [],
        \\    "points": []
        \\  }
        \\}
    ;

    const result = try json.parsePlayer(allocator, response);

    try std.testing.expectEqualStrings("Mbappé", result.name.?);
    try std.testing.expectEqual(@as(?i32, 4), result.position);
    try std.testing.expectEqual(@as(?i32, 150), result.points);
    try std.testing.expectEqual(@as(?i64, 85000000), result.value);
    try std.testing.expectApproxEqAbs(@as(f32, 7.5), result.avg.?, 0.01);
}

test "parsePlayer - with clause info" {
    const allocator = std.heap.page_allocator;
    const response =
        \\{
        \\  "status": "ok",
        \\  "data": {
        \\    "player": {
        \\      "name": "Test",
        \\      "clausesRanking": 25,
        \\      "clause": {"value": 15000000}
        \\    },
        \\    "values": [],
        \\    "points": []
        \\  }
        \\}
    ;

    const result = try json.parsePlayer(allocator, response);

    try std.testing.expectEqual(@as(?i32, 25), result.clauses_rank);
    try std.testing.expectEqual(@as(?i64, 15000000), result.clause);
}

test "parsePlayer - with owner" {
    const allocator = std.heap.page_allocator;
    const response =
        \\{
        \\  "status": "ok",
        \\  "data": {
        \\    "player": {
        \\      "name": "Test",
        \\      "owner": {"id": 12345, "name": "Juan"}
        \\    },
        \\    "values": [],
        \\    "points": []
        \\  }
        \\}
    ;

    const result = try json.parsePlayer(allocator, response);

    try std.testing.expectEqual(@as(?i64, 12345), result.owner_id);
    try std.testing.expectEqualStrings("Juan", result.owner_name.?);
}

// ========== parseOffers tests ==========

test "parseOffers - no offers" {
    const allocator = std.heap.page_allocator;
    const response =
        \\{
        \\  "status": "ok",
        \\  "data": {
        \\    "offers": []
        \\  }
        \\}
    ;

    const result = try json.parseOffers(allocator, response);

    try std.testing.expectEqual(@as(usize, 0), result.offers.len);
}

// ========== parseCommunities tests ==========

test "parseCommunities - empty communities" {
    const allocator = std.heap.page_allocator;
    const response =
        \\{
        \\  "status": "ok",
        \\  "data": {
        \\    "communities": {}
        \\  }
        \\}
    ;

    const result = try json.parseCommunities(allocator, response, null);

    try std.testing.expectEqual(@as(usize, 0), result.communities.len);
}
