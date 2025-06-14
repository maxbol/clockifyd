const std = @import("std");
const fs = std.fs;
const json = std.json;
const mem = std.mem;

pub const Values = struct {
    CLOCKIFY_CLI_BIN: []const u8,
    CLOCKIFY_CLI_CFG: []const u8,
    TEMPLATE_STR: []const u8,
    UNIX_SOCKET_PATH: []const u8 = "/tmp/clockifyd.sock",
    SPAWN_SERVER: bool,
};

allocator: std.mem.Allocator,
values: Values,
data_ref: DataRef,

const DataRef = union(enum) {
    env: *std.process.EnvMap,
    json: *json.Parsed(Values),

    fn deinit(data_ref: DataRef) void {
        switch (data_ref) {
            inline else => |ref| ref.deinit(),
        }
    }
};

fn createFromEnv(allocator: std.mem.Allocator) !@This() {
    var env_map = try std.process.getEnvMap(allocator);
    errdefer env_map.deinit();

    const home_env = env_map.get("HOME") orelse "/tmp";

    var default_clockify_cfg = std.ArrayList(u8).init(allocator);
    errdefer default_clockify_cfg.deinit();

    try default_clockify_cfg.appendSlice(home_env);
    try default_clockify_cfg.appendSlice("/.clockify-cli.yaml");

    const values = Values{
        .CLOCKIFY_CLI_BIN = env_map.get("CLOCKIFY_CLI_BIN") orelse "clockify-cli",
        .CLOCKIFY_CLI_CFG = env_map.get("CLOCKIFY_CLI_CFG") orelse try default_clockify_cfg.toOwnedSlice(),
        .TEMPLATE_STR = env_map.get("TEMPLATE_STR") orelse "{{ .Project.ClientName }} 󰁕 {{ .Project.Name }}",
        .UNIX_SOCKET_PATH = env_map.get("UNIX_SOCKET_PATH") orelse "/tmp/clockifyd.sock",
        .SPAWN_SERVER = mem.eql(u8, env_map.get("SPAWN_SERVER") orelse "0", "1"),
    };

    return .{
        .allocator = allocator,
        .values = values,
        .data_ref = DataRef{ .env = &env_map },
    };
}

pub fn init(allocator: std.mem.Allocator) !@This() {
    return createFromEnv(allocator);
}

pub fn deinit(cfg: *@This()) void {
    cfg.data_ref.deinit();
}
