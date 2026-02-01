const std = @import("std");
const config = @import("../config.zig");

pub const TokenData = struct {
    refresh: ?[]const u8 = null,
    xauth: std.json.ArrayHashMap([]const u8) = .{},
    current_community: ?[]const u8 = null,
};

pub const TokenService = struct {
    allocator: std.mem.Allocator,
    tokens_file: []const u8,
    data: TokenData,
    json_content: ?[]const u8 = null, // Keep JSON content alive for string references

    pub fn init(allocator: std.mem.Allocator) !TokenService {
        const cfg = config.Config.init();
        var service = TokenService{
            .allocator = allocator,
            .tokens_file = cfg.tokens_file,
            .data = .{},
        };

        // Try to load existing tokens
        service.load() catch {
            // If file doesn't exist, use defaults
            service.data.refresh = cfg.refresh_token;
        };

        return service;
    }

    pub fn deinit(self: *TokenService) void {
        if (self.json_content) |content| {
            self.allocator.free(content);
        }
    }

    pub fn load(self: *TokenService) !void {
        const file = std.fs.cwd().openFile(self.tokens_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return error.FileNotFound;
            }
            return err;
        };
        defer file.close();

        // Free old content if reloading
        if (self.json_content) |old_content| {
            self.allocator.free(old_content);
        }

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        self.json_content = content; // Keep content alive - parsed data references it

        const parsed = std.json.parseFromSlice(TokenData, self.allocator, content, .{}) catch {
            return error.InvalidJson;
        };
        self.data = parsed.value;
    }

    pub fn save(self: *TokenService) !void {
        const file = try std.fs.cwd().createFile(self.tokens_file, .{});
        defer file.close();

        // Write JSON to a buffer, then to file
        var write_buf: [4096]u8 = undefined;
        var file_writer = file.writer(&write_buf);
        const json_formatter = std.json.fmt(self.data, .{ .whitespace = .indent_2 });
        try json_formatter.format(&file_writer.interface);
        try file_writer.interface.flush();
    }

    pub fn getRefreshToken(self: *TokenService) ?[]const u8 {
        if (self.data.refresh) |r| return r;
        return config.Config.init().refresh_token;
    }

    pub fn setRefreshToken(self: *TokenService, token: []const u8) !void {
        self.data.refresh = token;
        try self.save();
    }

    pub fn getXAuth(self: *TokenService, community_id: []const u8) ?[]const u8 {
        return self.data.xauth.map.get(community_id);
    }

    pub fn setXAuth(self: *TokenService, community_id: []const u8, token: []const u8) !void {
        try self.data.xauth.map.put(self.allocator, community_id, token);
        try self.save();
    }

    pub fn getCurrentCommunity(self: *TokenService) ?[]const u8 {
        return self.data.current_community;
    }

    pub fn setCurrentCommunity(self: *TokenService, community_id: ?[]const u8) !void {
        self.data.current_community = community_id;
        try self.save();
    }

    pub fn getCurrentCommunityInt(self: *TokenService) ?i64 {
        const id = self.data.current_community orelse return null;
        return std.fmt.parseInt(i64, id, 10) catch null;
    }

    pub fn listTokens(self: *TokenService) std.json.ArrayHashMap([]const u8) {
        return self.data.xauth;
    }
};
