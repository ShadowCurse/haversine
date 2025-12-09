const std = @import("std");

pub const EARTH_RADIUS = 6372.8;

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
