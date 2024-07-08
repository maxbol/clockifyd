const std = @import("std");
const Config = @import("config.zig");
const Clockify = @import("clockify.zig");
const api = @import("api.zig");
const zul = @import("zul");

var current_display: []const u8 = "Loading...";
var current_display_buf: [512 * 1024]u8 = undefined;
var lock = std.Thread.Mutex{};
var cfg: Config = undefined;

fn shutdown(int: i32) callconv(.C) void {
    _ = int;
    std.log.info("Shutting down, goodbye!", .{});

    const socket_path = cfg.values.UNIX_SOCKET_PATH;

    std.fs.accessAbsolute(socket_path, .{}) catch {
        std.debug.print("Socket file does not exist, nothing to do.\n", .{});
        return;
    };

    std.fs.deleteFileAbsolute(socket_path) catch {
        std.debug.print("Failed to delete socket file, exiting anyway.\n", .{});
        return;
    };

    std.posix.exit(0);
}

fn registerSigIntHandler() !void {
    const action = std.posix.Sigaction{
        .handler = .{ .handler = &shutdown },
        .mask = 0,
        .flags = 0,
    };

    try std.posix.sigaction(std.posix.SIG.INT, &action, null);
    try std.posix.sigaction(std.posix.SIG.TERM, &action, null);
    try std.posix.sigaction(std.posix.SIG.HUP, &action, null);
}

fn handleRequest(req: api.ClientMsg) api.ServerMsg {
    switch (req.operation) {
        api.OperationType.GET_CURRENT_DISPLAY => {
            return api.ServerMsg{
                .result = api.ServerMsgType.SUCCESS,
                .body = current_display,
            };
        },
    }
}

fn readAndProcessSocketMessages(child_allocator: std.mem.Allocator, reader: anytype, writer: anytype) !void {
    errdefer {
        _ = writer.write(&api.server_is_going_down) catch |err| {
            std.log.err("Failed to write terminal signal unix socket: {!}\n", .{err});
        };
    }

    var arena = std.heap.ArenaAllocator.init(child_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const req_raw = reader.readUntilDelimiterOrEofAlloc(allocator, api.SENTINEL, 1024) catch |err| {
        std.log.err("Failed to read from unix socket: {!}\n", .{err});
        return error.ReadSocketError;
    } orelse {
        return;
    };

    const req = api.ClientMsg.parse(req_raw) catch |err| {
        std.log.err("Failed to parse request: {!}\n", .{err});
        return error.ParseRequestError;
    };

    const res = handleRequest(req);

    const res_raw = res.serialize(allocator) catch |err| {
        std.log.err("Failed to serialize response: {!}\n", .{err});
        return error.SerializeResponseError;
    };

    _ = writer.write(res_raw) catch |err| {
        std.log.err("Failed to write to unix socket: {!}\n", .{err});
        return error.WriteSocketError;
    };
}

fn setupUnixSocketListener() !std.net.Server {
    const socket_path = cfg.values.UNIX_SOCKET_PATH;

    var file_exists = true;

    std.debug.print("Socket path: {s}\n", .{socket_path});

    std.fs.accessAbsolute(socket_path, .{}) catch {
        file_exists = false;
    };

    if (file_exists) {
        std.log.err("Server already running, exiting...", .{});

        std.posix.exit(1);

        return;
    }

    try registerSigIntHandler();

    const addr = std.net.Address.initUnix(socket_path) catch |err| {
        std.log.err("Failed to create unix socket address: {!}\n", .{err});
        return err;
    };

    const server = addr.listen(.{}) catch |err| {
        std.log.err("Failed to listen on unix socket: {!}\n", .{err});
        return err;
    };

    std.log.info("Accepting connections on {s}", .{server.listen_address.un.path});

    return server;
}

fn listenOnUnixSocket() void {
    var server = setupUnixSocketListener() catch {
        shutdown(1);
        return;
    };
    defer server.deinit();

    var fixed_buffer: [1024 * 1024]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&fixed_buffer);

    while (true) {
        const conn = server.accept() catch |err| {
            std.log.err("Failed to accept connection: {!}\n", .{err});
            shutdown(1);
            return;
        };

        const stream = conn.stream;
        defer stream.close();

        const reader = stream.reader();
        const writer = stream.writer();

        readAndProcessSocketMessages(fixed_buffer_allocator.allocator(), reader, writer) catch {
            shutdown(1);
            return;
        };
    }
}

fn updateCurrentDisplay() void {
    // Allocate one megabyte of memory on the stack, this should
    // reasonably be all we ever need.
    var fixed_buffer: [10 * 1024 * 1024]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&fixed_buffer);

    const allocator = fixed_buffer_allocator.allocator();

    const clockify = Clockify.init(&cfg.values);

    while (true) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        lock.lock();
        defer lock.unlock();

        var stream = std.io.fixedBufferStream(&current_display_buf);

        _ = clockify.getDisplay(arena.allocator(), stream.writer()) catch |err| {
            std.log.err("Unexpected error: {!}\n", .{err});
            shutdown(1);
            return;
        };

        current_display = stream.getWritten();

        std.time.sleep(200 * std.time.ns_per_ms);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    cfg = try Config.init(gpa.allocator());

    var wg = std.Thread.WaitGroup{};

    wg.spawnManager(updateCurrentDisplay, .{});
    wg.spawnManager(listenOnUnixSocket, .{});

    wg.wait();
}
