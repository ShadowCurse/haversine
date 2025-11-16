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
