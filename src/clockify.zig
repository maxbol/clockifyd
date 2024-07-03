const std = @import("std");
const Config = @import("config.zig");
const Clockify = @This();

pub const ClockifyCmdResult = struct {
    exit_code: u8,
    stdout: []const u8,
};

pub fn executeClockifyCmd(allocator: std.mem.Allocator, cmd: []const []const u8) !ClockifyCmdResult {
    const process = try std.process.Child.run(.{
        .argv = cmd,
        .allocator = allocator,
    });

    const term = process.term;

    const exit_code = switch (term) {
        .Exited => |exit_code| exit_code,
        inline else => {
            return error.CmdFailed;
        },
    };

    const stdout_len = process.stdout.len;

    if (stdout_len == 0) {
        return .{
            .stdout = "Idle",
            .exit_code = exit_code,
        };
    }

    if (process.stdout[stdout_len - 1] == '\n') {
        return .{
            .stdout = process.stdout[0 .. stdout_len - 1],
            .exit_code = exit_code,
        };
    }

    return .{
        .stdout = process.stdout,
        .exit_code = exit_code,
    };
}

cfg: *const Config.Values,

pub fn init(cfg: *const Config.Values) Clockify {
    return Clockify{ .cfg = cfg };
}

fn getActiveProjectCmd(clockify: *const Clockify, allocator: std.mem.Allocator) ![]const []const u8 {
    var cmd = std.ArrayList([]const u8).init(allocator);

    try cmd.append(clockify.cfg.CLOCKIFY_CLI_BIN);
    try cmd.append("--config");
    try cmd.append(clockify.cfg.CLOCKIFY_CLI_CFG);
    try cmd.append("show");
    try cmd.append("current");
    try cmd.append("-f");
    try cmd.append(clockify.cfg.TEMPLATE_STR);

    return cmd.toOwnedSlice();
}

fn getActiveDurationCmd(clockify: *const Clockify, allocator: std.mem.Allocator) ![]const []const u8 {
    var cmd = std.ArrayList([]const u8).init(allocator);

    try cmd.append(clockify.cfg.CLOCKIFY_CLI_BIN);
    try cmd.append("--config");
    try cmd.append(clockify.cfg.CLOCKIFY_CLI_CFG);
    try cmd.append("show");
    try cmd.append("current");
    try cmd.append("-D");

    return cmd.toOwnedSlice();
}

fn getActiveProject(clockify: *const Clockify, allocator: std.mem.Allocator) !ClockifyCmdResult {
    const cmd = try clockify.getActiveProjectCmd(allocator);
    return executeClockifyCmd(allocator, cmd);
}

fn getActiveDuration(clockify: *const Clockify, allocator: std.mem.Allocator) !ClockifyCmdResult {
    const cmd = try clockify.getActiveDurationCmd(allocator);
    return executeClockifyCmd(allocator, cmd);
}

pub fn getDisplay(clockify: *const Clockify, allocator: std.mem.Allocator, out_buf: []u8) ![]const u8 {
    const project = try clockify.getActiveProject(allocator);

    if (project.exit_code != 0) {
        return "Idle";
    }

    const duration = try clockify.getActiveDuration(allocator);

    if (duration.exit_code != 0) {
        return std.fmt.bufPrint(out_buf, "{s}", .{project.stdout});
    }

    return std.fmt.bufPrint(out_buf, "{s} | {s}", .{ project.stdout, duration.stdout });
}

test "gets active project cmd correctly" {
    const cfg = Config.Values{ .CLOCKIFY_CLI_BIN = "clockify-cli", .CLOCKIFY_CLI_CFG = "config.json", .TEMPLATE_STR = "{{ .Project.ClientName }}" };

    const clockify = Clockify.init(&cfg);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cmd = try clockify.getActiveProjectCmd(arena.allocator());

    try std.testing.expect(std.mem.eql(u8, cmd[0], "clockify-cli"));
    try std.testing.expect(std.mem.eql(u8, cmd[1], "--config"));
    try std.testing.expect(std.mem.eql(u8, cmd[2], "config.json"));
    try std.testing.expect(std.mem.eql(u8, cmd[3], "show"));
    try std.testing.expect(std.mem.eql(u8, cmd[4], "current"));
    try std.testing.expect(std.mem.eql(u8, cmd[5], "-f"));
    try std.testing.expect(std.mem.eql(u8, cmd[6], "{{ .Project.ClientName }}"));
}

test "gets active duration cmd correctly" {
    const cfg = Config.Values{ .CLOCKIFY_CLI_BIN = "clockify-cli", .CLOCKIFY_CLI_CFG = "config.json", .TEMPLATE_STR = "{{ .Project.ClientName }}" };

    const clockify = Clockify.init(&cfg);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cmd = try clockify.getActiveDurationCmd(arena.allocator());

    try std.testing.expect(std.mem.eql(u8, cmd[0], "clockify-cli"));
    try std.testing.expect(std.mem.eql(u8, cmd[1], "--config"));
    try std.testing.expect(std.mem.eql(u8, cmd[2], "config.json"));
    try std.testing.expect(std.mem.eql(u8, cmd[3], "show"));
    try std.testing.expect(std.mem.eql(u8, cmd[4], "current"));
    try std.testing.expect(std.mem.eql(u8, cmd[5], "-D"));
}

test "gets active project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const home = try std.process.getEnvVarOwned(allocator, "HOME");

    var cfgPath = std.ArrayList(u8).init(allocator);

    try cfgPath.appendSlice(home);
    try cfgPath.appendSlice("/.clockify-cli.yaml");

    const cfg = Config.Values{ .CLOCKIFY_CLI_CFG = try cfgPath.toOwnedSlice(), .CLOCKIFY_CLI_BIN = "clockify-cli", .TEMPLATE_STR = "{{ .Project.ClientName }}" };

    const clockify = Clockify.init(&cfg);

    const result = try clockify.getActiveProject(allocator);

    try std.testing.expect(result.exit_code == 0);
}

test "gets active duration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const home = try std.process.getEnvVarOwned(allocator, "HOME");

    var cfgPath = std.ArrayList(u8).init(allocator);

    try cfgPath.appendSlice(home);
    try cfgPath.appendSlice("/.clockify-cli.yaml");

    const cfg = Config.Values{ .CLOCKIFY_CLI_CFG = try cfgPath.toOwnedSlice(), .CLOCKIFY_CLI_BIN = "clockify-cli", .TEMPLATE_STR = "{{ .Project.ClientName }}" };

    const clockify = Clockify.init(&cfg);

    const result = try clockify.getActiveDuration(allocator);

    try std.testing.expect(result.exit_code == 0);
}

test "gets display" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const home = try std.process.getEnvVarOwned(allocator, "HOME");

    var cfgPath = std.ArrayList(u8).init(allocator);

    try cfgPath.appendSlice(home);
    try cfgPath.appendSlice("/.clockify-cli.yaml");

    const cfg = Config.Values{ .CLOCKIFY_CLI_CFG = try cfgPath.toOwnedSlice(), .CLOCKIFY_CLI_BIN = "clockify-cli", .TEMPLATE_STR = "{{ .Project.ClientName }} 󰁕 {{ .Project.Name }}" };

    const clockify = Clockify.init(&cfg);

    var out_buf: [1024 * 1024]u8 = undefined;

    const result = try clockify.getDisplay(allocator, &out_buf);

    try std.testing.expect(result.len > 0);
}
