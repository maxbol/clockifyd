const std = @import("std");
const Config = @import("config.zig");
const Clockify = @import("clockify.zig");

var current_display: []const u8 = "Idle";
var current_display_buf: [512 * 1024]u8 = undefined;
var lock = std.Thread.Mutex{};

fn updateCurrentDisplay(cfg: *const Config) void {
    // Allocate one megabyte of memory on the stack, this should
    // reasonably be all we ever need.
    var fixed_buffer: [10 * 1024 * 1024]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&fixed_buffer);

    const allocator = fixed_buffer_allocator.allocator();

    const clockify = Clockify.init(&cfg.values);

    const stdOutWriter = std.io.getStdOut().writer();

    while (true) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        lock.lock();
        defer lock.unlock();

        current_display = clockify.getDisplay(arena.allocator(), &current_display_buf) catch |err| {
            std.log.err("Unexpected error: {!}\n", .{err});
            std.log.err("Exiting thread...", .{});
            break;
        };

        const std_out_data = std.fmt.allocPrint(allocator, "\x1B[2KDisplay: {s}", .{current_display}) catch |err| {
            std.log.err("Unexpected error: {!}\n", .{err});
            std.log.err("Exiting thread...", .{});
            break;
        };

        _ = stdOutWriter.write(std_out_data) catch |err| {
            std.log.err("Unexpected error: {!}\n", .{err});
            std.log.err("Exiting thread...", .{});
            break;
        };

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const cfg = try Config.init(gpa.allocator());

    var wg = std.Thread.WaitGroup{};

    wg.spawnManager(updateCurrentDisplay, .{&cfg});

    wg.wait();
}
