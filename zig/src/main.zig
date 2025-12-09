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
    if (args.len < 2 or 3 < args.len) {
        std.log.err("Incorrect number of args: {d}.", .{args.len - 1});
        return;
    }
    const input_path = std.mem.span(args[1]);
    const answers_path = if (args.len == 3) std.mem.span(args[2]) else null;

    const input_file_mem = try mmap_file(input_path);
    const answers_file_mem = if (answers_path) |ap| try mmap_file(ap) else null;
    const answers = if (answers_file_mem) |afm| @as([]const f64, @ptrCast(afm)) else null;

    const max_pairs_bytes = input_file_mem.len & ~(@as(u64, @sizeOf(Pair)) - 1);
    const pair_buffer_mem = std.posix.mmap(
        null,
        max_pairs_bytes,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |e| {
        std.log.err("Error mmaping the pair buffer: {t}", .{e});
        return e;
    };
    var pair_index: u32 = 0;
    const pairs: []Pair = @ptrCast(pair_buffer_mem);

    var parser: Json = .init(input_file_mem);

    _ = try expect_token_type(&parser, .object_start);
    _ = try expect_token_type(&parser, .string);
    _ = try expect_token_type(&parser, .array_start);

    {
        const prof_json = prof.start_named("json parse");
        defer prof.end_with_bytes(prof_json, input_file_mem.len);

        while (true) {
            if (parser.peek_array_end()) break;

            const pair = try Pair.from_json_parser(&parser);
            pairs[pair_index] = pair;
            pair_index += 1;
        }
    }

    const sum = blk: {
        const prof_haversine = prof.start_named("haversine");
        defer prof.end_with_bytes(prof_haversine, @sizeOf(Pair) * pair_index);

        const sum = loop_sum(pairs[0..pair_index]);
        break :blk sum;
    };
    const average = sum / @as(f64, @floatFromInt(pair_index));
    std.log.info("Average: {d} of {d} pairs", .{ average, pair_index });
    if (answers) |ans| {
        const result = loop_verify(pairs[0..pair_index], ans);
        if (result.has_errors())
            std.log.info(
                "Individual erros: {d}/{d} Final sum error: {}",
                .{ result.individual_errors, pair_index, result.final_sum_error },
            );
    }
    const ranges = loop_find_ranges(pairs[0..pair_index]);
    std.log.info("Input/Output ranges:", .{});
    std.log.info("in_sin:  {d:>6.3} ..{d:>6.3} out_sin:  {d:>6.3} ..{d:>6.3}", .{
        ranges.in_sin.min,
        ranges.in_sin.max,
        ranges.out_sin.min,
        ranges.out_sin.max,
    });
    std.log.info("in_cos:  {d:>6.3} ..{d:>6.3} out_cos:  {d:>6.3} ..{d:>6.3}", .{
        ranges.in_cos.min,
        ranges.in_cos.max,
        ranges.out_cos.min,
        ranges.out_cos.max,
    });
    std.log.info("in_asin: {d:>6.3} ..{d:>6.3} out_asin: {d:>6.3} ..{d:>6.3}", .{
        ranges.in_asin.min,
        ranges.in_asin.max,
        ranges.out_asin.min,
        ranges.out_asin.max,
    });
    std.log.info("in_sqrt: {d:>6.3} ..{d:>6.3} out_sqrt: {d:>6.3} ..{d:>6.3}", .{
        ranges.in_sqrt.min,
        ranges.in_sqrt.max,
        ranges.out_sqrt.min,
        ranges.out_sqrt.max,
    });
}

fn loop_sum(pairs: []const Pair) f64 {
    var sum: f64 = 0.0;
    for (pairs) |pair| {
        const dist = haversine.haversine(
            pair.x0,
            pair.y0,
            pair.x1,
            pair.y1,
            haversine.EARTH_RADIUS,
        );
        sum += dist;
    }
    return sum;
}

const VerifyResult = struct {
    individual_errors: u64,
    final_sum_error: bool,

    fn has_errors(self: *const VerifyResult) bool {
        return self.individual_errors != 0 or self.final_sum_error;
    }
};
fn loop_verify(pairs: []const Pair, answers: []const f64) VerifyResult {
    var sum: f64 = 0.0;
    var individual_errors: u64 = 0;
    for (pairs, 0..) |pair, i| {
        const dist = haversine.haversine(
            pair.x0,
            pair.y0,
            pair.x1,
            pair.y1,
            haversine.EARTH_RADIUS,
        );
        sum += dist;
        if (!close_values(dist, answers[i])) individual_errors += 1;
    }
    const average = sum / @as(f64, @floatFromInt(pairs.len));
    const final_sum_error = !close_values(average, answers[answers.len - 1]);
    return .{
        .individual_errors = individual_errors,
        .final_sum_error = final_sum_error,
    };
}

fn loop_find_ranges(pairs: []const Pair) haversine.MathRanges {
    var ranges: haversine.MathRanges = .{};
    for (pairs) |pair| {
        _ = haversine.haversine_with_ranges(
            pair.x0,
            pair.y0,
            pair.x1,
            pair.y1,
            haversine.EARTH_RADIUS,
            &ranges,
        );
    }
    return ranges;
}

fn close_values(a: f64, b: f64) bool {
    const EPSILON = 0.000000001;
    const diff = a - b;
    return -EPSILON < diff and diff < EPSILON;
}

fn mmap_file(path: []const u8) ![]align(std.heap.page_size_min) u8 {
    const file_fd = std.posix.open(path, .{ .ACCMODE = .RDWR }, 0) catch |e| {
        std.log.err("Error openning the file {s}: {t}", .{ path, e });
        return e;
    };
    defer std.posix.close(file_fd);

    const file_stat = statx(file_fd) catch |e| {
        std.log.err("Error getting file stats: {t}", .{e});
        return e;
    };

    const file_mem = std.posix.mmap(
        null,
        file_stat.size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE },
        file_fd,
        0,
    ) catch |e| {
        std.log.err("Error mmaping the input file: {t}", .{e});
        return e;
    };

    return file_mem;
}

fn statx(fd: std.posix.fd_t) !std.os.linux.Statx {
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
