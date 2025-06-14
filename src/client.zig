const std = @import("std");
const api = @import("api.zig");
const Config = @import("config.zig");
const clap = @import("clap");

fn attemptToSpawnServer(cfg: *const Config, allocator: std.mem.Allocator) !std.net.Stream {
    const socket_path = cfg.values.UNIX_SOCKET_PATH;

    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    var server_exe = std.ArrayList(u8).init(allocator);
    try server_exe.appendSlice(exe_path);
    try server_exe.appendSlice("/clockifyd");

    const server_exe_slice = try server_exe.toOwnedSlice();

    try std.fs.accessAbsolute(server_exe_slice, .{});

    var server_proc = std.process.Child.init(&.{server_exe_slice}, allocator);
    var env_map = try std.process.getEnvMap(allocator);
    server_proc.env_map = &env_map;

    try server_proc.spawn();

    var remaining_attemps: u8 = 20;

    return while (true) {
        break std.net.connectUnixSocket(socket_path) catch |err| {
            switch (err) {
                error.FileNotFound, error.ConnectionRefused => {
                    if (remaining_attemps == 0) {
                        return err;
                    }
                    remaining_attemps -= 1;
                    std.time.sleep(std.time.ns_per_ms * 200);
                    continue;
                },
                else => {
                    return err;
                },
            }
        };
    };
}

fn makeApiCall(allocator: std.mem.Allocator, cfg: *const Config) !?[]const u8 {
    const socket_path = cfg.values.UNIX_SOCKET_PATH;

    const stream = std.net.connectUnixSocket(socket_path) catch |err| switch (err) {
        error.FileNotFound, error.ConnectionRefused => if (cfg.values.SPAWN_SERVER) attemptToSpawnServer(cfg, allocator) catch |spawn_err| {
            std.log.err("Failed to spawn server: {!}\n", .{spawn_err});
            @panic("Connection refused\n");
        } else err,
        else => err,
    } catch |err| {
        std.log.err("Failed to connect to unix socket: {!}\n", .{err});
        return err;
    };
    defer stream.close();

    const writer = stream.writer();
    const reader = stream.reader();

    const msg = api.ClientMsg{
        .operation = .GET_CURRENT_DISPLAY,
        .channel_id = 0,
    };

    const serialized_msg = msg.serialize(allocator) catch |err| {
        std.log.err("Failed to serialize message: {!}\n", .{err});
        return err;
    };

    _ = writer.write(serialized_msg) catch |err| {
        std.log.err("Failed to write message: {!}\n", .{err});
        return err;
    };

    const server_msg_raw = reader.readUntilDelimiterAlloc(allocator, api.SENTINEL, 1024) catch |err| {
        std.log.err("Failed to read message: {!}\n", .{err});
        return err;
    };

    const server_msg = api.ServerMsg.parse(server_msg_raw) catch |err| {
        std.log.err("Failed to parse message: {!}\n", .{err});
        return err;
    };

    switch (server_msg.result) {
        .SUCCESS => {
            return server_msg.body;
        },
        .WRONG_API_VERSION => {
            std.log.err("Server has wrong API version\n", .{});
            return error.WrongApiVersion;
        },
        .INVALID_OPERATION => {
            std.log.err("Invalid operation\n", .{});
            return error.InvalidOperation;
        },
        inline else => {
            std.log.err("Unknown error\n", .{});
            return error.UnknownError;
        },
    }
}

pub fn main() !void {
    var fixed_buffer: [1024 * 1024 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    const allocator = fba.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Show this message
        \\-s, --spawn-server    Attempt to spawn server if it's not running
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, &.{}, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    var cfg = try Config.init(allocator);

    if (res.args.@"spawn-server" != 0) {
        cfg.values.SPAWN_SERVER = true;
    }

    const out_data = makeApiCall(allocator, &cfg) catch {
        std.process.exit(1);
    };

    if (out_data) |data| {
        std.io.getStdOut().writeAll(data) catch |err| {
            std.log.err("Failed to write to stdout: {!}\n", .{err});
            std.process.exit(1);
        };
    }

    std.process.exit(0);
}
