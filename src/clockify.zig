const std = @import("std");
const Config = @import("config.zig");
const Clockify = @This();
const zul = @import("zul");

pub const ClockifyCmdResult = struct {
    exit_code: u8,
    stdout: []const u8,
};

pub const ClockifyParsedResult = struct {
    id: []const u8,
    project: struct {
        name: []const u8,
        clientName: []const u8,
    },
    timeInterval: struct { start: zul.DateTime },
};

const MICROSECONDS_IN_A_DAY = 86_400_000_000;
const MICROSECONDS_IN_AN_HOUR = 3_600_000_000;
const MICROSECONDS_IN_A_MIN = 60_000_000;
const MICROSECONDS_IN_A_SEC = 1_000_000;

fn getTimeWithoutMicrosFromMicros(micros: u64) zul.Time {
    return .{
        .hour = @intCast(@divTrunc(
            micros,
            MICROSECONDS_IN_AN_HOUR,
        )),
        .min = @intCast(@divTrunc(
            @rem(micros, MICROSECONDS_IN_AN_HOUR),
            MICROSECONDS_IN_A_MIN,
        )),
        .sec = @intCast(@divTrunc(
            @rem(micros, MICROSECONDS_IN_A_MIN),
            MICROSECONDS_IN_A_SEC,
        )),
        .micros = 0,
    };
}

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

    if (process.stdout.len > 0 and process.stdout[stdout_len - 1] == '\n') {
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
    try cmd.append("-j");

    return cmd.toOwnedSlice();
}

fn getActiveProject(clockify: *const Clockify, allocator: std.mem.Allocator) !ClockifyCmdResult {
    const cmd = try clockify.getActiveProjectCmd(allocator);
    return executeClockifyCmd(allocator, cmd);
}

fn parseActiveProject(result: ClockifyCmdResult, allocator: std.mem.Allocator) !std.json.Parsed([]ClockifyParsedResult) {
    return std.json.parseFromSlice([]ClockifyParsedResult, allocator, result.stdout, .{ .ignore_unknown_fields = true });
}

pub fn getDisplay(clockify: *const Clockify, allocator: std.mem.Allocator, out: anytype) !void {
    const project = try clockify.getActiveProject(allocator);

    if (project.exit_code != 0 or project.stdout.len == 0) {
        _ = try out.write("Idle");
        return;
    }

    const parsed_project = try parseActiveProject(project, allocator);

    if (parsed_project.value.len == 0) {
        _ = try out.write("Idle");
        return;
    }

    const parsed_result = parsed_project.value[0];

    const start_micros = parsed_result.timeInterval.start.micros;
    const now_micros = zul.DateTime.now().micros;

    const duration: u64 = @intCast(now_micros - start_micros);

    const duration_ts = getTimeWithoutMicrosFromMicros(duration);

    try std.fmt.format(out, "{s} 󰁕 {s} | ", .{ parsed_result.project.clientName, parsed_result.project.name });
    try duration_ts.format("", .{}, out);
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
    try std.testing.expect(std.mem.eql(u8, cmd[5], "-j"));
}
