const std = @import("std");
const Config = @import("config.zig");
const Clockify = @import("clockify.zig");
const api = @import("api.zig");

var current_display: []const u8 = "Idle";
var current_display_buf: [512 * 1024]u8 = undefined;
var lock = std.Thread.Mutex{};

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

fn setupUnixSocketListener(cfg: *const Config) !std.net.Server {
    const socket_path = cfg.values.UNIX_SOCKET_PATH;

    var file_exists = true;

    std.fs.accessAbsolute(socket_path, .{}) catch {
        file_exists = false;
    };

    if (file_exists) {
        std.fs.deleteFileAbsolute(socket_path) catch |err| {
            std.log.err("Failed to delete existing unix socket file: {!}\n", .{err});
            return err;
        };
    }

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

fn listenOnUnixSocket(cfg: *const Config) void {
    var server = setupUnixSocketListener(cfg) catch {
        @panic("Critical error, exiting...");
    };
    defer server.deinit();

    var fixed_buffer: [1024 * 1024]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&fixed_buffer);

    while (true) {
        const conn = server.accept() catch |err| {
            std.log.err("Failed to accept connection: {!}\n", .{err});
            @panic("Critical error, exiting...");
        };

        const stream = conn.stream;
        defer stream.close();

        const reader = stream.reader();
        const writer = stream.writer();

        readAndProcessSocketMessages(fixed_buffer_allocator.allocator(), reader, writer) catch {
            @panic("Critical error, exiting...");
        };
    }
}

fn updateCurrentDisplay(cfg: *const Config) void {
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

        current_display = clockify.getDisplay(arena.allocator(), &current_display_buf) catch |err| {
            std.log.err("Unexpected error: {!}\n", .{err});
            @panic("Critical error, exiting...");
        };

        std.time.sleep(200 * std.time.ns_per_ms);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const cfg = try Config.init(gpa.allocator());

    var wg = std.Thread.WaitGroup{};

    wg.spawnManager(updateCurrentDisplay, .{&cfg});
    wg.spawnManager(listenOnUnixSocket, .{&cfg});

    wg.wait();
}
