const std = @import("std");
const api = @import("api.zig");
const Config = @import("Config.zig");

fn makeApiCall(allocator: std.mem.Allocator, cfg: *const Config) !?[]const u8 {
    const socket_path = cfg.values.UNIX_SOCKET_PATH;

    const stream = std.net.connectUnixSocket(socket_path) catch |err| {
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const cfg = try Config.init(gpa.allocator());

    const out_data = makeApiCall(gpa.allocator(), &cfg) catch {
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
