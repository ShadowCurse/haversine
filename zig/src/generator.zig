const std = @import("std");
const haversine = @import("haversine");

pub fn main() !void {
    const args = std.os.argv;
    if (args.len != 4) {
        std.log.err("Incorrect number of args: {d}/3", .{args.len - 1});
        return;
    }
    const seed_arg = std.mem.span(args[1]);
    const num_pairs_arg = std.mem.span(args[2]);
    const cluster_size_arg = std.mem.span(args[3]);

    const seed = std.fmt.parseInt(u64, seed_arg, 10) catch |e| {
        std.log.err("Error parsing seed value: {t}", .{e});
        return;
    };
    const num_pairs = std.fmt.parseInt(u64, num_pairs_arg, 10) catch |e| {
        std.log.err("Error parsing number of pairs: {t}", .{e});
        return;
    };
    const cluster_size = std.fmt.parseInt(u64, cluster_size_arg, 10) catch |e| {
        std.log.err("Error parsing cluster size: {t}", .{e});
        return;
    };

    const pairs_file_fd = try open_file("pairs", "json", num_pairs);
    defer std.posix.close(pairs_file_fd);

    const answer_file_fd = try open_file("answer", "txt", num_pairs);
    defer std.posix.close(answer_file_fd);

    const answer_file_bin_fd = try open_file("answer", "bin", num_pairs);
    defer std.posix.close(answer_file_bin_fd);

    var random: Random = .init(seed);
    const num_clusters = blk: {
        var c = num_pairs / cluster_size;
        if (num_pairs % cluster_size != 0) c += 1;
        break :blk c;
    };
    var average: f64 = 0.0;

    try write_file(pairs_file_fd, "{{\n  \"pairs\": [\n", .{});
    defer write_file(pairs_file_fd, "]}}", .{}) catch unreachable;

    for (0..num_clusters) |c| {
        const cluster_x0 = random.random_in_range(-180.0, 180.0);
        const cluster_y0 = random.random_in_range(-90.0, 90.0);
        const cluster_x1 = random.random_in_range(-180.0, 180.0);
        const cluster_y1 = random.random_in_range(-90.0, 90.0);
        const radius = random.random_in_range(-20.0, 20.0);
        for (0..cluster_size) |i| {
            const x0 = random_in_cluster(&random, cluster_x0, -radius, radius, -180.0, 180.0);
            const y0 = random_in_cluster(&random, cluster_y0, -radius, radius, -90.0, 90.0);
            const x1 = random_in_cluster(&random, cluster_x1, -radius, radius, -180.0, 180.0);
            const y1 = random_in_cluster(&random, cluster_y1, -radius, radius, -90.0, 90.0);
            if (c == num_clusters - 1 and i == cluster_size - 1) {
                try write_file(
                    pairs_file_fd,
                    "    {{ \"x0\": {d}, \"y0\": {d}, \"x1\": {d}, \"y1\": {d} }}\n",
                    .{ x0, y0, x1, y1 },
                );
            } else {
                try write_file(
                    pairs_file_fd,
                    "    {{ \"x0\": {d}, \"y0\": {d}, \"x1\": {d}, \"y1\": {d} }},\n",
                    .{ x0, y0, x1, y1 },
                );
            }
            const dist = haversine.haversine(x0, y0, x1, y1, haversine.EARTH_RADIUS);
            average += dist;

            try write_file(answer_file_fd, "{d}\n", .{dist});
            try write_file_bin(answer_file_bin_fd, @ptrCast(&dist));
        }
    }
    average /= @floatFromInt(num_pairs);
    try write_file(answer_file_fd, "{d}", .{average});
    try write_file_bin(answer_file_bin_fd, @ptrCast(&average));
    std.log.info("Average: {d} of {d} pairs", .{ average, num_pairs });
}

fn open_file(name: []const u8, ext: []const u8, num_pairs: u64) !std.posix.fd_t {
    var name_buf: [256]u8 = undefined;
    const file_name = std.fmt.bufPrint(
        &name_buf,
        "{s}_{d}.{s}",
        .{ name, num_pairs, ext },
    ) catch |e| {
        std.log.err(
            "Cannot format file name with name: {s} ext: {s} num_pairs: {d} error: {t}",
            .{ name, ext, num_pairs, e },
        );
        return e;
    };

    const fd = std.posix.open(
        file_name,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        std.os.linux.S.IRWXU,
    ) catch |e| {
        std.log.err("Error openning the file {s}: {t}", .{ file_name, e });
        return e;
    };
    return fd;
}

fn write_file(
    fd: std.posix.fd_t,
    comptime format: []const u8,
    args: anytype,
) !void {
    var buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, format, args) catch |e| {
        std.log.err("Cannot format json line", .{});
        return e;
    };
    _ = std.posix.write(fd, line) catch |e| {
        std.log.err("Cannot write to the file: {t}", .{e});
        return e;
    };
}

fn write_file_bin(
    fd: std.posix.fd_t,
    bytes: []const u8,
) !void {
    _ = std.posix.write(fd, bytes) catch |e| {
        std.log.err("Cannot write to the file: {t}", .{e});
        return e;
    };
}

fn random_in_cluster(
    random: *Random,
    cluster: f64,
    cluster_min: f64,
    cluster_max: f64,
    total_min: f64,
    total_max: f64,
) f64 {
    var v = cluster + random.random_in_range(cluster_min, cluster_max);
    if (v < total_min) v = total_min;
    if (total_max < v) v = total_max;
    return v;
}

const Random = struct {
    a: u64,
    b: u64,
    c: u64,
    d: u64,

    const Self = @This();

    fn init(seed: u64) Self {
        var self: Self = .{
            .a = 0xf1ea5eed,
            .b = seed,
            .c = seed,
            .d = seed,
        };

        for (0..20) |_| _ = self.random();

        return self;
    }

    fn rotate_left(v: u64, shift: u64) u64 {
        return v << @truncate(shift) | v >> @truncate(64 - shift);
    }
    fn random(self: *Self) u64 {
        const e = self.a -% Self.rotate_left(self.b, 27);

        const a = self.b ^ Self.rotate_left(self.c, 17);
        const b = self.c +% self.d;
        const c = self.d +% e;
        const d = e +% a;

        self.a = a;
        self.b = b;
        self.c = c;
        self.d = d;

        return d;
    }

    fn random_in_range(self: *Self, min: f64, max: f64) f64 {
        var ratio: f64 = @floatFromInt(self.random());
        ratio /= @floatFromInt(std.math.maxInt(u64));
        return min + (max - min) * ratio;
    }
};
