const std = @import("std");
const spice = @import("spice");
const proto = @import("proto/service.zig");
const transport = @import("transport.zig");
const compression = @import("features/compression.zig");
const auth = @import("features/auth.zig");
const streaming = @import("features/streaming.zig");
const health = @import("features/health.zig");

pub const Handler = struct {
    name: []const u8,
    handler_fn: *const fn ([]const u8, std.mem.Allocator) anyerror![]u8,
};

pub const GrpcServer = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    server: std.net.Server,
    handlers: std.ArrayList(Handler),
    compression: compression.Compression,
    auth: auth.Auth,
    health_check: health.HealthCheck,
    requests_processed: usize = 0,
    request_limit: ?usize = null,

    pub fn init(allocator: std.mem.Allocator, port: u16, secret_key: []const u8, request_limit: ?usize) !GrpcServer {
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        const server = try address.listen(.{
            .reuse_address = true,
        });
        
        return GrpcServer{
            .allocator = allocator,
            .address = address,
            .server = server,
            .handlers = .{},
            .compression = compression.Compression.init(allocator),
            .auth = auth.Auth.init(allocator, secret_key),
            .health_check = health.HealthCheck.init(allocator),
            .request_limit = request_limit,
        };
    }

    pub fn deinit(self: *GrpcServer) void {
        self.handlers.deinit(self.allocator);
        // self.server.deinit(); // std.net.Server doesn't have deinit
        self.health_check.deinit();
    }

    pub fn start(self: *GrpcServer) !void {
        // listen is already called in init
        try self.health_check.setStatus("grpc.health.v1.Health", .SERVING);
        std.log.info("Server listening on {any}", .{self.address});

        while (true) {
            if (self.request_limit) |limit| {
                if (self.requests_processed >= limit) {
                    std.log.info("Request limit reached ({}), shutting down.", .{limit});
                    break;
                }
            }
            const connection = try self.server.accept();
            try self.handleConnection(connection);
        }
    }

    fn handleConnection(self: *GrpcServer, conn: std.net.Server.Connection) !void {
        var trans = try transport.Transport.init(self.allocator, conn.stream, true);
        defer trans.deinit();

        // Setup streaming
        var message_stream = streaming.MessageStream.init(self.allocator, 1024);
        defer message_stream.deinit();

        while (true) {
            const message = trans.readMessage() catch |err| switch (err) {
                error.ConnectionClosed => break,
                else => return err,
            };

            // Verify auth token from headers
            // try self.auth.verifyToken(message.headers.get("authorization") orelse "");

            defer self.allocator.free(message);

            // Process message
            for (self.handlers.items) |handler| {
                self.requests_processed += 1;
                const response = try handler.handler_fn(message, self.allocator);
                defer self.allocator.free(response);

                try trans.writeMessage(response);
            }
            
            if (self.request_limit) |limit| {
                if (self.requests_processed >= limit) break;
            }
        }
    }
};
