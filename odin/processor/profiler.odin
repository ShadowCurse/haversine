package processor

import "base:runtime"
import "core:fmt"
import "core:time"

tsc_freq :: proc() -> u64 {
    s := get_perf_counter()
    time.sleep(1000_000)
    e := get_perf_counter()
    return (e - s) * 1000
}

when ODIN_ARCH == .amd64 {
    get_perf_counter :: time.read_cycle_counter
}
when ODIN_ARCH == .amd64 {
    get_perf_counter_frequency :: tsc_freq
}

ProfPoint :: struct {
    start_time:            u64,
    parent:                ^Measurement,
    current:               ^Measurement,
    current_with_children: u64,
}

Measurement :: struct {
    without_children: u64,
    with_children:    u64,
    hit_count:        u64,
    bytes_count:      u64,
    name:             [^]u8,
}

perf_global_start: u64 = 0
perf_global_freq: u64 = 0
@(thread_local)
perf_tl_current: ^Measurement
@(thread_local)
perf_tl_measurements: [32]Measurement

profile_start :: proc() {
    perf_global_freq = get_perf_counter_frequency()
    perf_global_start = get_perf_counter()
}

profile_end :: proc() {
    fmt.printfln("Counter frequency: %d", perf_global_freq)
    global_end := get_perf_counter()
    global_elapsed: f64 = cast(f64)global_end - cast(f64)perf_global_start
    for m in perf_tl_measurements {
        if m.name == nil do continue
        without_children_t: f64 = cast(f64)m.without_children / cast(f64)perf_global_freq
        without_children: f64 = cast(f64)m.without_children / global_elapsed * 100.0
        with_children_t: f64 = cast(f64)m.with_children / cast(f64)perf_global_freq
        with_children: f64 = cast(f64)m.with_children / global_elapsed * 100.0
        bytes_per_second: f64 = 0.0
        gigabytes_per_second: f64 = 0.0
        if m.bytes_count != 0 {
            bytes_per_second = cast(f64)m.bytes_count / cast(f64)with_children_t
            gigabytes_per_second = bytes_per_second / (1024.0 * 1024.0 * 1024.0)
        }
        fmt.printfln(
            "%-10s | hit: % 6d | exclusive: % 6fs (% 6f%%) | inclusive: % 6fs (%f 6%%) | throughput: % 6f Gbps",
            m.name,
            m.hit_count,
            without_children_t,
            without_children,
            with_children_t,
            with_children,
            gigabytes_per_second,
        )

    }
}

profile_point_start :: proc(index: u32) -> ProfPoint {
    parent := perf_tl_current
    perf_tl_current = &perf_tl_measurements[index]
    return {
        start_time = get_perf_counter(),
        parent = parent,
        current = perf_tl_current,
        current_with_children = perf_tl_current.with_children,
    }
}
profile_point_end :: proc(point: ProfPoint, name: string, #any_int bytes: u64 = 0) {
    end_time := get_perf_counter()
    elapsed := end_time - point.start_time
    point.current.name = raw_data(name)
    point.current.hit_count += 1
    point.current.bytes_count += bytes
    point.current.without_children += elapsed
    point.current.with_children = point.current_with_children + elapsed
    if point.parent != nil do point.parent.without_children -= elapsed
    perf_tl_current = point.parent
}
