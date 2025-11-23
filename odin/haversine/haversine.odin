package haversine

import "core:math"

EARTH_RADIUS :: 6372.8

radians_from_degrees :: proc(degrees: f64) -> f64 {
    return degrees / 360.0 * math.PI * 2.0
}

haversine :: proc(x0: f64, y0: f64, x1: f64, y1: f64, radius: f64) -> f64 {
    lat_1 := y0
    lat_2 := y1
    lon_1 := x0
    lon_2 := x1

    d_lat := radians_from_degrees(lat_2 - lat_1)
    d_lon := radians_from_degrees(lon_2 - lon_1)
    lat_1 = radians_from_degrees(lat_1)
    lat_2 = radians_from_degrees(lat_2)

    a :=
        (math.sin(d_lat / 2.0) * math.sin(d_lat / 2.0)) +
        math.cos(lat_1) * math.cos(lat_2) * (math.sin(d_lon / 2) * math.sin(d_lon / 2))
    c := 2.0 * math.asin(math.sqrt(a))

    return radius * c
}
