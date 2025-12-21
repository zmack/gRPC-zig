const std = @import("std");

pub const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
};

pub const FrameFlags = struct {
    pub const END_STREAM = 0x1;
    pub const END_HEADERS = 0x4;
    pub const PADDED = 0x8;
    pub const PRIORITY = 0x20;
};

pub const Frame = struct {
    length: u24,
    type: FrameType,
    flags: u8,
    stream_id: u31,
    payload: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Frame {
        return Frame{
            .length = 0,
            .type = .DATA,
            .flags = 0,
            .stream_id = 0,
            .payload = try allocator.alloc(u8, 0),
        };
    }

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }

    pub fn encode(self: Frame, writer: anytype) !void {
        var buf: [9]u8 = undefined;
        std.mem.writeInt(u24, buf[0..3], self.length, .big);
        buf[3] = @intFromEnum(self.type);
        buf[4] = self.flags;
        std.mem.writeInt(u32, buf[5..9], self.stream_id, .big);
        _ = try writer.write(&buf);
        _ = try writer.write(self.payload);
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !Frame {
        var frame = try Frame.init(allocator);
        
        var buf3: [3]u8 = undefined;
        {
            var index: usize = 0;
            while (index < 3) {
                const n = try reader.read(buf3[index..]);
                if (n == 0) return error.EndOfStream;
                index += n;
            }
        }
        frame.length = std.mem.readInt(u24, &buf3, .big);

        var buf1: [1]u8 = undefined;
        {
            var index: usize = 0;
            while (index < 1) {
                const n = try reader.read(buf1[index..]);
                if (n == 0) return error.EndOfStream;
                index += n;
            }
        }
        frame.type = @enumFromInt(buf1[0]);

        {
            var index: usize = 0;
            while (index < 1) {
                const n = try reader.read(buf1[index..]);
                if (n == 0) return error.EndOfStream;
                index += n;
            }
        }
        frame.flags = buf1[0];

        var buf4: [4]u8 = undefined;
        {
            var index: usize = 0;
            while (index < 4) {
                const n = try reader.read(buf4[index..]);
                if (n == 0) return error.EndOfStream;
                index += n;
            }
        }
        const sid = std.mem.readInt(u32, &buf4, .big);
        frame.stream_id = @intCast(sid & 0x7FFFFFFF);
        
        const payload = try allocator.alloc(u8, frame.length);
        {
            var index: usize = 0;
            while (index < frame.length) {
                const n = try reader.read(payload[index..]);
                if (n == 0) return error.EndOfStream;
                index += n;
            }
        }
        frame.payload = payload;
        
        return frame;
    }
};
