const std = @import("std");

pub const Compression = struct {
    pub const Algorithm = enum {
        none,
        gzip,
        deflate,
    };

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compression {
        return .{ .allocator = allocator };
    }

    pub fn compress(self: *Compression, data: []const u8, algorithm: Algorithm) ![]u8 {
        // Compression is currently disabled due to changes in Zig std.compress API
        _ = algorithm;
        return self.allocator.dupe(u8, data);
    }

    pub fn decompress(self: *Compression, data: []const u8, algorithm: Algorithm) ![]u8 {
        // Decompression is currently disabled due to changes in Zig std.compress API
        _ = algorithm;
        return self.allocator.dupe(u8, data);
    }
};