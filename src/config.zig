const std = @import("std");

pub const Config = struct {
    port: u16,
    host: []const u8,
    tokens_file: []const u8,
    refresh_token: ?[]const u8,

    pub fn init() Config {
        return .{
            .port = getEnvInt("PORT", 8080),
            .host = getEnv("HOST", "0.0.0.0"),
            .tokens_file = getEnv("TOKENS_FILE", "tokens.json"),
            .refresh_token = std.posix.getenv("REFRESH"),
        };
    }

    fn getEnv(key: []const u8, default: []const u8) []const u8 {
        return std.posix.getenv(key) orelse default;
    }

    fn getEnvInt(key: []const u8, default: u16) u16 {
        const val = std.posix.getenv(key) orelse return default;
        return std.fmt.parseInt(u16, val, 10) catch default;
    }
};

pub const FANTASY_BASE_URL = "fantasy.marca.com";
pub const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3";
pub const FREE_AGENT = "Libre";
pub const SELLING_TEXT = "En venta";
pub const MARKET_NAME = "Fantasy MARCA";
