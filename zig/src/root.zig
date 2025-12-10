const std = @import("std");

pub const EARTH_RADIUS = 6372.8;

fn sin(input: f64) f64 {
    const A = -1.0 / 6.0;
    const B = 1.0 / 120.0;
    const C = -1.0 / 5040.0;
    const D = 1.0 / 362880.0;
    const E = -1.0 / 39916800.0;
    const x2 = input * input;
    // Use Taylor series with max power of x^11
    // The formula with carried out terms is
    // x * (x^2 * (x^2 * (x^2 * (x^2 * (E * x^2 + D) + C) + B) + A) + 1)
    var result = x2 * E + D;
    result *= x2;
    result += C;
    result *= x2;
    result += B;
    result *= x2;
    result += A;
    result *= x2;
    result += 1.0;
    result *= input;
    return result;
}

fn cos(input: f64) f64 {
    return sin(input + std.math.pi / 2.0);
}

fn asin(input: f64) f64 {
    return input;
}

fn sqrt(input: f64) f64 {
    const result = asm volatile (
        \\ sqrtsd %[ret], %[input]
        : [ret] "={xmm0}" (-> f64),
        : [input] "{xmm0}" (input),
    );
    return result;
}

pub fn radians_from_degrees(degrees: f64) f64 {
    return degrees / 360.0 * std.math.pi * 2.0;
}

pub fn haversine(x0: f64, y0: f64, x1: f64, y1: f64, radius: f64) f64 {
    var lat_1 = y0;
    var lat_2 = y1;
    const lon_1 = x0;
    const lon_2 = x1;

    const d_lat = radians_from_degrees(lat_2 - lat_1);
    const d_lon = radians_from_degrees(lon_2 - lon_1);
    lat_1 = radians_from_degrees(lat_1);
    lat_2 = radians_from_degrees(lat_2);

    const a = (@sin(d_lat / 2.0) * @sin(d_lat / 2.0)) +
        @cos(lat_1) * @cos(lat_2) * (@sin(d_lon / 2) * @sin(d_lon / 2));
    const c = 2.0 * std.math.asin(@sqrt(a));

    return radius * c;
}

pub const Range = struct {
    min: f64 = std.math.floatMax(f64),
    max: f64 = std.math.floatMin(f64),
    pub fn record(self: *Range, value: f64) void {
        self.min = @min(self.min, value);
        self.max = @max(self.max, value);
    }
};

pub const MathRanges = struct {
    in_sin: Range = .{},
    in_cos: Range = .{},
    in_asin: Range = .{},
    in_sqrt: Range = .{},
    out_sin: Range = .{},
    out_cos: Range = .{},
    out_asin: Range = .{},
    out_sqrt: Range = .{},

    pub fn sin(self: *MathRanges, input: f64) f64 {
        self.in_sin.record(input);
        const result = @sin(input);
        self.out_sin.record(result);
        return result;
    }

    pub fn cos(self: *MathRanges, input: f64) f64 {
        self.in_cos.record(input);
        const result = @cos(input);
        self.out_cos.record(result);
        return result;
    }

    pub fn asin(self: *MathRanges, input: f64) f64 {
        self.in_asin.record(input);
        const result = std.math.asin(input);
        self.out_asin.record(result);
        return result;
    }

    pub fn sqrt(self: *MathRanges, input: f64) f64 {
        self.in_sqrt.record(input);
        const result = @sqrt(input);
        self.out_sqrt.record(result);
        return result;
    }
};

pub fn haversine_with_ranges(
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    radius: f64,
    ranges: *MathRanges,
) f64 {
    var lat_1 = y0;
    var lat_2 = y1;
    const lon_1 = x0;
    const lon_2 = x1;

    const d_lat = radians_from_degrees(lat_2 - lat_1);
    const d_lon = radians_from_degrees(lon_2 - lon_1);
    lat_1 = radians_from_degrees(lat_1);
    lat_2 = radians_from_degrees(lat_2);

    const a = (ranges.sin(d_lat / 2.0) * ranges.sin(d_lat / 2.0)) +
        ranges.cos(lat_1) * ranges.cos(lat_2) * (ranges.sin(d_lon / 2) * ranges.sin(d_lon / 2));
    const c = 2.0 * ranges.asin(ranges.sqrt(a));

    return radius * c;
}

test "sin_accuracy" {
    const MIN = -3.142;
    const MAX = 3.142;
    const SAMPLES = 1000_000;

    const D = MAX - MIN;
    var max_diff: f64 = 0.0;
    for (0..SAMPLES) |i| {
        const progress: f64 = @as(f64, @floatFromInt(i)) / SAMPLES;
        const value = MIN + D * progress;

        const original = @sin(value);
        const custom = sin(value);
        const diff = @abs(custom - original);
        max_diff = @max(max_diff, diff);
    }
    std.debug.print("sin max_diff: {d:.24}\n", .{max_diff});
}

test "cos_accuracy" {
    const MIN = -1.571;
    const MAX = 1.571;
    const SAMPLES = 1000_000;

    const D = MAX - MIN;
    var max_diff: f64 = 0.0;
    for (0..SAMPLES) |i| {
        const progress: f64 = @as(f64, @floatFromInt(i)) / SAMPLES;
        const value = MIN + D * progress;

        const original = @cos(value);
        const custom = cos(value);
        const diff = @abs(custom - original);
        max_diff = @max(max_diff, diff);
    }
    std.debug.print("cos max_diff: {d:.24}\n", .{max_diff});
}

test "asin_accuracy" {
    const MIN = 0.0;
    const MAX = 1.0;
    const SAMPLES = 1000_000;

    const D = MAX - MIN;
    var max_diff: f64 = 0.0;
    for (0..SAMPLES) |i| {
        const progress: f64 = @as(f64, @floatFromInt(i)) / SAMPLES;
        const value = MIN + D * progress;

        const original = std.math.asin(value);
        const custom = asin(value);
        const diff = @abs(custom - original);
        max_diff = @max(max_diff, diff);
    }
    std.debug.print("asin max_diff: {d:.24}\n", .{max_diff});
}

test "sqrt_accuracy" {
    const MIN = 0.0;
    const MAX = 1.0;
    const SAMPLES = 1000_000;

    const D = MAX - MIN;
    var max_diff: f64 = 0.0;
    for (0..SAMPLES) |i| {
        const progress: f64 = @as(f64, @floatFromInt(i)) / SAMPLES;
        const value = MIN + D * progress;

        const original = @sqrt(value);
        const custom = sqrt(value);
        const diff = @abs(custom - original);
        max_diff = @max(max_diff, diff);
    }
    std.debug.print("sqrt max_diff: {d:.24}\n", .{max_diff});
}
