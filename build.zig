const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});

    const spice_dep = b.dependency("spice", .{});
    const spice_mod = spice_dep.module("spice");

    const grpc_mod = b.addModule("grpc", .{
        .root_source_file = b.path("src/lib.zig"),
    });
    grpc_mod.addImport("spice", spice_mod);
}
