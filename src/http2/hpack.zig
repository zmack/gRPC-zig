const std = @import("std");

pub const HpackError = error{
    InvalidIndex,
    BufferTooSmall,
    InvalidHuffmanCode,
};

pub const Encoder = struct {
    dynamic_table: std.ArrayList(HeaderField),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Encoder {
        return Encoder{
            .dynamic_table = std.ArrayList(HeaderField){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Encoder) void {
        for (self.dynamic_table.items) |field| {
            self.allocator.free(field.name);
            self.allocator.free(field.value);
        }
        self.dynamic_table.deinit(self.allocator);
    }

    pub fn encode(self: *Encoder, headers: std.StringHashMap([]const u8)) ![]u8 {
        var buffer = std.ArrayList(u8){};
        errdefer buffer.deinit(self.allocator);

        var it = headers.iterator();
        while (it.next()) |entry| {
            try self.encodeField(&buffer, entry.key_ptr.*, entry.value_ptr.*, self.allocator);
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn encodeField(self: *Encoder, buffer: *std.ArrayList(u8), name: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
        // Simple literal header field encoding
        try buffer.append(allocator, 0x0); // New name
        try self.encodeString(buffer, name, allocator);
        try self.encodeString(buffer, value, allocator);
    }

    fn encodeString(self: *Encoder, buffer: *std.ArrayList(u8), str: []const u8, allocator: std.mem.Allocator) !void {
        _ = self;
        try buffer.append(allocator, @intCast(str.len));
        try buffer.appendSlice(allocator, str);
    }
};

pub const Decoder = struct {
    dynamic_table: std.ArrayList(HeaderField),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Decoder {
        return Decoder{
            .dynamic_table = std.ArrayList(HeaderField){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Decoder) void {
        for (self.dynamic_table.items) |field| {
            self.allocator.free(field.name);
            self.allocator.free(field.value);
        }
        self.dynamic_table.deinit(self.allocator);
    }

    pub fn decode(self: *Decoder, encoded: []const u8) !std.StringHashMap([]const u8) {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer headers.deinit();

        var i: usize = 0;
        while (i < encoded.len) {
            const field = try self.decodeField(encoded[i..]);
            try headers.put(field.name, field.value);
            i += field.len;
        }

        return headers;
    }

    fn decodeField(self: *Decoder, encoded: []const u8) !HeaderField {
        if (encoded[0] == 0x0) {
            // Literal header field
            const name_len = encoded[1];
            const name = encoded[2..2+name_len];
            const value_len = encoded[2+name_len];
            const value = encoded[3+name_len..3+name_len+value_len];
            
            return HeaderField{
                .name = try self.allocator.dupe(u8, name),
                .value = try self.allocator.dupe(u8, value),
                .len = 3 + name_len + value_len,
            };
        }
        return HpackError.InvalidIndex;
    }
};

const HeaderField = struct {
    name: []const u8,
    value: []const u8,
    len: usize = 0,
};