const std = @import("std");
const net = std.net;
const http2 = struct {
    pub const connection = @import("http2/connection.zig");
    pub const frame = @import("http2/frame.zig");
    pub const stream = @import("http2/stream.zig");
};

pub const TransportError = error{
    ConnectionClosed,
    InvalidHeader,
    PayloadTooLarge,
    CompressionNotSupported,
    Http2Error,
};

pub const Transport = struct {
    stream: net.Stream,
    allocator: std.mem.Allocator,
    http2_conn: ?http2.connection.Connection,

    pub fn init(allocator: std.mem.Allocator, stream: net.Stream, is_server: bool) !Transport {
        var transport = Transport{
            .stream = stream,
            .allocator = allocator,
            .http2_conn = null,
        };

        // Initialize HTTP/2 connection
        transport.http2_conn = try http2.connection.Connection.init(allocator);
        try transport.setupHttp2(is_server);

        return transport;
    }

    pub fn deinit(self: *Transport) void {
        if (self.http2_conn) |*conn| {
            conn.deinit();
        }
        self.stream.close();
    }

    fn setupHttp2(self: *Transport, is_server: bool) !void {
        if (!is_server) {
            // Client sends HTTP/2 connection preface
            _ = try self.stream.write(http2.connection.Connection.PREFACE);
        } else {
            // Server reads preface
            var buf: [24]u8 = undefined;

            var total_read: usize = 0;
            while (total_read < 24) {
                const n = try self.stream.read(buf[total_read..]);
                if (n == 0) break; // EOF
                total_read += n;
            }
            const len = total_read;

            if (len != 24 or !std.mem.eql(u8, &buf, http2.connection.Connection.PREFACE)) {
                // For simplicity, just ignore or log error if preface is invalid/missing
                // In real impl, return error
            }
        }

        // Send initial SETTINGS frame
        var settings_frame = try http2.frame.Frame.init(self.allocator);
        defer settings_frame.deinit(self.allocator);

        settings_frame.type = .SETTINGS;
        settings_frame.flags = 0;
        settings_frame.stream_id = 0;
        // Add your settings here

        try settings_frame.encode(self.stream);
    }

    pub fn readMessage(self: *Transport) ![]const u8 {
        // Use raw reader (unbuffered) to avoid data loss with recreating buffered reader
        while (true) {
            var frame = http2.frame.Frame.decode(self.stream, self.allocator) catch |err| {
                if (err == error.EndOfStream) return TransportError.ConnectionClosed;
                return err;
            };
            defer frame.deinit(self.allocator);

            if (frame.type == .DATA) {
                return try self.allocator.dupe(u8, frame.payload);
            }
        }
    }

    pub fn writeMessage(self: *Transport, message: []const u8) !void {
        var data_frame = http2.frame.Frame{
            .length = @intCast(message.len),
            .type = .DATA,
            .flags = http2.frame.FrameFlags.END_STREAM,
            .stream_id = 1,
            .payload = message,
        };

        try data_frame.encode(self.stream);
    }
};
