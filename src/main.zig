const std = @import("std");
const haversine = @import("haversine");

const profiler = @import("profiler.zig");
const Json = @import("json.zig");

pub const profiler_options = profiler.Options{
    .enabled = true,
};

pub const prof = profiler.Measurements("main", &.{
    "json parse",
    "haversine",
    "main2",
});

pub fn main() !void {
    profiler.start();

    try main2();

    profiler.print(&.{ prof, Json.prof });
}

pub fn main2() !void {
    const prof_point = prof.start(@src());
    defer prof.end(prof_point);

    const args = std.os.argv;
    if (args.len != 2) {
        std.log.err("Incorrect number of args: {d}/1", .{args.len - 1});
        return;
    }
    const file_path = std.mem.span(args[1]);

    const file_fd = std.posix.open(file_path, .{ .ACCMODE = .RDONLY }, 0) catch |e| {
        std.log.err("Error openning the file {s}: {t}", .{ file_path, e });
        return e;
    };
    defer std.posix.close(file_fd);

    const s = statx(file_fd) catch |e| {
        std.log.err("Error getting file stats: {t}", .{e});
        return e;
    };

    const file_mem = std.posix.mmap(
        null,
        s.size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file_fd,
        0,
    ) catch |e| {
        std.log.err("Error mmaping the file: {t}", .{e});
        return e;
    };

    const max_pairs_bytes = s.size & ~(@as(u64, @sizeOf(Pair)) - 1);
    const pair_buffer_mem = std.posix.mmap(
        null,
        max_pairs_bytes,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
        },
        -1,
        0,
    ) catch |e| {
        std.log.err("Error mmaping the pair buffer: {t}", .{e});
        return e;
    };
    var pair_index: u32 = 0;
    const pairs: []Pair = @ptrCast(pair_buffer_mem);

    var parser: Json = .init(file_mem);

    _ = try expect_token_type(&parser, .object_start);
    _ = try expect_token_type(&parser, .string);
    _ = try expect_token_type(&parser, .array_start);

    {
        const prof_json = prof.start_named("json parse");
        defer prof.end(prof_json);
        while (true) {
            if (parser.peek_array_end()) break;

            const pair = try Pair.from_json_parser(&parser);
            pairs[pair_index] = pair;
            pair_index += 1;
        }
    }

    {
        const prof_haversine = prof.start_named("haversine");
        defer prof.end(prof_haversine);
        var average: f64 = 0.0;
        for (pairs[0..pair_index]) |pair| {
            const dist = haversine.haversine(
                pair.x0,
                pair.y0,
                pair.x1,
                pair.y1,
                haversine.EARTH_RADIUS,
            );
            average += dist;
        }
        average /= @floatFromInt(pair_index);
        std.log.info("Average: {d} of {d} pairs", .{ average, pair_index });
    }
}

pub fn statx(fd: std.posix.fd_t) !std.os.linux.Statx {
    var stx = std.mem.zeroes(std.os.linux.Statx);
    const rcx = std.os.linux.statx(
        fd,
        "\x00",
        std.os.linux.AT.EMPTY_PATH,
        std.os.linux.STATX_TYPE |
            std.os.linux.STATX_MODE |
            std.os.linux.STATX_ATIME |
            std.os.linux.STATX_MTIME |
            std.os.linux.STATX_BTIME,
        &stx,
    );

    switch (std.posix.errno(rcx)) {
        .SUCCESS => {},
        else => |e| return std.posix.unexpectedErrno(e),
    }
    return stx;
}

fn expect_token_type(parser: *Json, expected_token_type: Json.TokenType) ![]const u8 {
    if (parser.next()) |token| {
        if (std.meta.activeTag(token) != expected_token_type) {
            std.log.err("Got invalid token: {any}", .{token});
            return error.InvalidToken;
        }
        switch (token) {
            .string => |s| return s,
            .number => |n| return n,
            else => return &.{},
        }
    } else {
        return error.NoToken;
    }
}

const Pair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,

    const Self = @This();

    fn from_json_parser(parser: *Json) !Self {
        const Inner = struct {
            fn parse_field(p: *Json, field_name: []const u8) !f64 {
                const s = try expect_token_type(p, .string);
                if (!std.mem.eql(u8, s, field_name)) {
                    std.log.err("Got invalid token string: {s}", .{s});
                    return error.InvalidToken;
                }
                const x0_str = try expect_token_type(p, .number);
                const r = std.fmt.parseFloat(f64, x0_str) catch |e| {
                    std.log.err(
                        "Error parsing field {s}: got string: {s} {t}",
                        .{ field_name, x0_str, e },
                    );
                    return e;
                };
                return r;
            }
        };

        _ = try expect_token_type(parser, .object_start);
        const x0 = try Inner.parse_field(parser, "x0");
        const y0 = try Inner.parse_field(parser, "y0");
        const x1 = try Inner.parse_field(parser, "x1");
        const y1 = try Inner.parse_field(parser, "y1");
        _ = try expect_token_type(parser, .object_end);

        return .{ .x0 = x0, .y0 = y0, .x1 = x1, .y1 = y1 };
    }
};
