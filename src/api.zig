const std = @import("std");

// Denotes breaking API versions
const API_VERSION: u8 = 1;

pub const SENTINEL = '\n';

pub const OperationType = enum {
    GET_CURRENT_DISPLAY,
};

pub const ServerMsgType = enum {
    SUCCESS,
    WRONG_API_VERSION,
    UNEXPECTED_ERROR,
    INVALID_OPERATION,
    SERVER_IS_GOING_DOWN,
};

pub const ClientMsg = struct {
    operation: OperationType,
    channel_id: u8 = 0,
    body: ?[]const u8 = null,
    pub fn serialize(self: ClientMsg, allocator: std.mem.Allocator) ![]const u8 {
        var req_serialized = std.ArrayList(u8).init(allocator);

        // Tag client msg with API version
        try req_serialized.append(API_VERSION);

        // Tag client msg with channel_id
        try req_serialized.append(self.channel_id);

        // Set operation type
        try req_serialized.append(@intFromEnum(self.operation));

        // Set response body
        if (self.body) |body| {
            try req_serialized.appendSlice(body);
        }

        // Append sentinel
        try req_serialized.append(SENTINEL);

        return req_serialized.toOwnedSlice();
    }

    pub fn parse(serialized: []const u8) !ClientMsg {
        if (serialized.len < 3) {
            return error.MalformedRequest;
        }
        var i: usize = 0;

        // Check API version
        if (serialized[i] != API_VERSION) {
            return error.WrongApiVersion;
        }

        i += 1;

        // Get channel_id
        const channel_id: u8 = serialized[i];
        i += 1;

        // Get operation type
        const operation: OperationType = @enumFromInt(serialized[i]);
        i += 1;

        // Get body
        var body: ?[]const u8 = null;
        if (i < serialized.len) {
            body = serialized[i..];
        }

        return .{ .channel_id = channel_id, .operation = operation, .body = body };
    }
};

pub const ServerMsg = struct {
    result: ServerMsgType,
    channel_id: u8 = 0,
    body: ?[]const u8 = null,

    pub fn serialize(response: ServerMsg, allocator: std.mem.Allocator) ![]const u8 {
        var res_serialized = std.ArrayList(u8).init(allocator);

        // Tag response with API version
        try res_serialized.append(API_VERSION);

        // Tag response with channel_id
        try res_serialized.append(response.channel_id);

        // Set result type
        try res_serialized.append(@intFromEnum(response.result));

        // Set response body
        if (response.body) |body| {
            try res_serialized.appendSlice(body);
        }

        // Append sentinel
        try res_serialized.append(SENTINEL);

        return res_serialized.toOwnedSlice();
    }

    pub fn parse(serialized: []const u8) !ServerMsg {
        if (serialized.len < 2) {
            return error.MalformedResponse;
        }
        var i: usize = 0;

        // Check API version
        if (serialized[i] != API_VERSION) {
            return error.WrongApiVersion;
        }

        i += 1;

        // Get channel_id
        const channel_id: u8 = serialized[i];
        i += 1;

        // Get result type
        const result: ServerMsgType = @enumFromInt(serialized[i]);
        i += 1;

        // Get body
        var body: ?[]const u8 = null;
        if (i < serialized.len) {
            body = serialized[i..];
        }

        return .{ .channel_id = channel_id, .result = result, .body = body };
    }
};

pub const server_is_going_down: [3]u8 = .{ API_VERSION, @intFromEnum(ServerMsgType.SERVER_IS_GOING_DOWN), SENTINEL };
