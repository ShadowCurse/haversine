package generator

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:sys/linux"

import "haversine"

main :: proc() {
    args := os.args
    if len(args) != 4 {
        fmt.eprintfln("Incorrect number of args: %d/3", len(args) - 1)
        return
    }
    parse_ok: bool = ---
    seed: u64 = ---
    num_pairs: u64 = ---
    cluster_size: u64 = ---
    seed, parse_ok = strconv.parse_u64_of_base(args[1], 10)
    if !parse_ok {
        fmt.eprintln("Error parsing seed value")
        return
    }
    num_pairs, parse_ok = strconv.parse_u64_of_base(args[2], 10)
    if !parse_ok {
        fmt.eprintln("Error parsing number of pairs")
        return
    }
    cluster_size, parse_ok = strconv.parse_u64_of_base(args[3], 10)
    if !parse_ok {
        fmt.eprintln("Error parsing cluster size")
        return
    }

    file_ok: bool = ---
    pairs_file_fd: os.Handle = ---
    answer_file_fd: os.Handle = ---
    pairs_file_fd, file_ok = open_file("pairs", "json", num_pairs)
    if !file_ok do return
    defer os.close(pairs_file_fd)

    answer_file_fd, file_ok = open_file("answer", "txt", num_pairs)
    if !file_ok do return
    defer os.close(answer_file_fd)

    random := random_init(seed)
    num_clusters := num_pairs / cluster_size
    if num_pairs % cluster_size != 0 do num_clusters += 1
    average: f64 = 0.0

    fmt.fprintf(pairs_file_fd, "{{\n \"pairs\": [\n")
    defer fmt.fprintf(pairs_file_fd, "]}}")

    for c in 0 ..< num_clusters {
        cluster_x0 := random_in_range(&random, -180.0, 180.0)
        cluster_y0 := random_in_range(&random, -90.0, 90.0)
        cluster_x1 := random_in_range(&random, -180.0, 180.0)
        cluster_y1 := random_in_range(&random, -90.0, 90.0)
        r := random_in_range(&random, -20.0, 20.0)
        for i in 0 ..< cluster_size {
            x0 := random_in_cluster(&random, cluster_x0, -r, r, -180.0, 180.0)
            y0 := random_in_cluster(&random, cluster_y0, -r, r, -90.0, 90.0)
            x1 := random_in_cluster(&random, cluster_x1, -r, r, -180.0, 180.0)
            y1 := random_in_cluster(&random, cluster_y1, -r, r, -90.0, 90.0)

            ending := ","
            if c == num_clusters - 1 && i == cluster_size - 1 do ending = ","

            fmt.fprintf(
                pairs_file_fd,
                "    {{ \"x0\": %.12f, \"y0\": %.12f, \"x1\": %.12f, \"y1\": %.12f }}%s\n",
                x0,
                y0,
                x1,
                y1,
                ending,
            )
            dist := haversine.haversine(x0, y0, x1, y1, haversine.EARTH_RADIUS)
            average += dist

            fmt.fprintf(answer_file_fd, "%.12f\n", dist)
        }
    }
    average /= cast(f64)num_pairs
    fmt.fprintf(
        answer_file_fd,
        "Average: %.12f of %d pairs",
        average,
        num_pairs,
    )
    fmt.printfln("Average: %.12f of %d pairs", average, num_pairs)
}

open_file :: proc(
    name: string,
    ext: string,
    num_pairs: u64,
) -> (
    os.Handle,
    bool,
) {
    name_buf: [256]u8 = ---
    file_name := fmt.bprintf(name_buf[:], "%s_%d.%s\x00", name, num_pairs, ext)
    fd, errno := os.open(
        file_name,
        os.O_RDWR | os.O_CREATE | os.O_TRUNC,
        0o700,
    )
    if errno != .NONE {
        fmt.eprintfln(
            "Error openning the file %s: %s",
            file_name,
            os.error_string(errno),
        )
        return 0, false
    }
    return fd, true
}

Random :: struct {
    a: u64,
    b: u64,
    c: u64,
    d: u64,
}

random_init :: proc(seed: u64) -> Random {
    random := Random {
        a = 0xf1ea5eed,
        b = seed,
        c = seed,
        d = seed,
    }
    for _ in 0 ..< 20 do random_u64(&random)
    return random
}

random_u64 :: proc(random: ^Random) -> u64 {

    rotate_left :: proc(v: u64, shift: u64) -> u64 {
        return v << shift | v >> (64 - shift)
    }

    e := random.a - rotate_left(random.b, 27)
    a := random.b ~ rotate_left(random.c, 17)
    b := random.c + random.d
    c := random.d + e
    d := e + a

    random.a = a
    random.b = b
    random.c = c
    random.d = d

    return d
}

random_in_range :: proc(random: ^Random, min: f64, _max: f64) -> f64 {
    ratio := cast(f64)random_u64(random)
    ratio /= cast(f64)max(u64)
    return min + (_max - min) * ratio
}

random_in_cluster :: proc(
    random: ^Random,
    cluster: f64,
    cluster_min: f64,
    cluster_max: f64,
    total_min: f64,
    total_max: f64,
) -> f64 {
    v := cluster + random_in_range(random, cluster_min, cluster_max)
    if v < total_min do v = total_min
    if total_max < v do v = total_max
    return v
}
