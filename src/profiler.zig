const std = @import("std");
const builtin = @import("builtin");

pub var global_start: u64 = 0;
pub var global_freq: u64 = 0;
pub threadlocal var current: ?*Measurement = null;

pub const Options = struct {
    enabled: bool = false,
};

const root = @import("root");
pub const options: Options = if (@hasDecl(root, "profiler_options"))
    root.profiler_options
else
    .{};

pub const get_perf_counter = if (builtin.cpu.arch == .x86_64)
    rdtc
else
    @compileError("Only x86_64 is supported");

fn rdtc() u64 {
    var high: u64 = 0;
    var low: u64 = 0;
    asm volatile (
        \\rdtsc
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );
    return (high << 32) | low;
}

fn get_perf_counter_frequency() u64 {
    const s = get_perf_counter();
    std.Thread.sleep(1000_000);
    const e = get_perf_counter();
    return (e - s) * 1000;
}

pub const Measurement = struct {
    without_children: u64 = 0,
    with_children: u64 = 0,
    hit_count: u64 = 0,
};

pub fn start() void {
    global_freq = get_perf_counter_frequency();
    global_start = get_perf_counter();
}

pub fn Measurements(comptime FILE: []const u8, comptime NAMES: []const []const u8) type {
    return if (!options.enabled)
        struct {
            pub fn start(comptime _: std.builtin.SourceLocation) void {}
            pub fn start_named(comptime _: []const u8) void {}
            pub fn end(_: void) void {}
            pub fn print() void {}
        }
    else
        struct {
            pub var measurements: [NAMES.len]Measurement = .{Measurement{}} ** NAMES.len;

            pub const Point = struct {
                start_time: u64,
                parent: ?*Measurement,
                current: *Measurement,
                current_with_children: u64,
            };

            pub fn start(comptime src: std.builtin.SourceLocation) Point {
                return start_named(src.fn_name);
            }

            pub fn start_named(comptime name: []const u8) Point {
                const index = comptime blk: {
                    for (NAMES, 0..) |n, i| {
                        if (std.mem.eql(u8, n, name)) break :blk i;
                    }
                };
                const parent = current;
                current = &measurements[index];
                return .{
                    .start_time = get_perf_counter(),
                    .parent = parent,
                    .current = current.?,
                    .current_with_children = current.?.with_children,
                };
            }
            pub fn end(point: Point) void {
                const end_time = get_perf_counter();
                const elapsed = end_time - point.start_time;
                point.current.hit_count += 1;
                point.current.without_children +%= elapsed;
                point.current.with_children = point.current_with_children + elapsed;
                if (point.parent) |parent| parent.without_children -%= elapsed;
                current = point.parent;
            }

            pub fn print() void {
                const freq: f64 = @floatFromInt(global_freq);
                const global_end = get_perf_counter();
                const global_elapsed: f64 = @floatFromInt(global_end - global_start);
                for (NAMES, measurements) |name, m| {
                    const without_children_t: f64 =
                        @as(f64, @floatFromInt(m.without_children)) / freq;
                    const without_children: f64 =
                        @as(f64, @floatFromInt(m.without_children)) / global_elapsed * 100.0;
                    const with_children_t: f64 =
                        @as(f64, @floatFromInt(m.with_children)) / freq;
                    const with_children: f64 =
                        @as(f64, @floatFromInt(m.with_children)) / global_elapsed * 100.0;
                    std.log.info(
                        "{s}: {s:>20}: hit: {d:>6} exclusive: {d:>6.2}s ({d:>6.2}%) inclusive: {d:>6.2}s ({d:>6.2}%)",
                        .{
                            FILE,
                            name,
                            m.hit_count,
                            without_children_t,
                            without_children,
                            with_children_t,
                            with_children,
                        },
                    );
                }
            }
        };
}

pub fn print(comptime types: []const type) void {
    std.log.info("Counter frequency: {d}", .{global_freq});

    inline for (types) |t|
        t.print();

    const freq: f64 = @floatFromInt(global_freq);
    const global_end = get_perf_counter();
    const global_elapsed: f64 = @floatFromInt(global_end - global_start);
    const global_time = global_elapsed / freq;
    std.log.info("Total {d:>6.2}s ({d})", .{ global_time, global_elapsed });
}
