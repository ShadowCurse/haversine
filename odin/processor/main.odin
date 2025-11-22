package processor

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:sys/linux"

import "../haversine"

main :: proc() {
    args := os.args
    if len(args) != 2 {
        fmt.eprintfln("Incorrect number of args: %d/1", len(args) - 1)
        return
    }
    file_name := args[1]

    file_fd: os.Handle = ---
    errno: os.Error = ---
    file_fd, errno = os.open(file_name, os.O_RDONLY, 0)
    if errno != .NONE {
        fmt.eprintfln(
            "Error openning the file %s: %s",
            file_name,
            os.error_string(errno),
        )
        return
    }
    defer os.close(file_fd)

    file_size: i64 = ---
    file_size, errno = os.file_size(file_fd)
    if errno != .NONE {
        fmt.eprintfln(
            "Error getting the file size: %s",
            os.error_string(errno),
        )
        return
    }

    file_mem: rawptr = ---
    file_mem, errno = linux.mmap(
        {},
        cast(uint)file_size,
        {.READ},
        {.PRIVATE},
        cast(linux.Fd)file_fd,
        0,
    )
    if file_mem == nil {
        fmt.eprintfln("Error mmaping the file: %s", os.error_string(errno))
        return
    }
    json_text := slice.from_ptr(cast(^u8)file_mem, cast(int)file_size)

    max_pairs_bytes := file_size &~ (size_of(Pair) - 1)
    pair_buffer_mem: rawptr = ---
    pair_buffer_mem, errno = linux.mmap(
        {},
        cast(uint)max_pairs_bytes,
        {.READ, .WRITE},
        {.PRIVATE, .ANONYMOUS},
        -1,
        0,
    )
    if file_mem == nil {
        fmt.eprintfln(
            "Error mmaping the pair buffer: %s",
            os.error_string(errno),
        )
        return
    }
    pair_index: u32 = 0
    pairs: []Pair = slice.from_ptr(
        cast(^Pair)pair_buffer_mem,
        cast(int)max_pairs_bytes / size_of(Pair),
    )

    parser := json_init(json_text)

    if _, ok := expect_token_type(&parser, .object_start); !ok do return
    if _, ok := expect_token_type(&parser, .string); !ok do return
    if _, ok := expect_token_type(&parser, .array_start); !ok do return

    for {
        if json_peek_array_end(&parser) do break

        pair, ok := pair_from_json(&parser)
        if !ok do return

        pairs[pair_index] = pair
        pair_index += 1
    }

    average: f64 = ---
    for pair in pairs[0:pair_index] {
        dist := haversine.haversine(
            pair.x0,
            pair.y0,
            pair.x1,
            pair.y1,
            haversine.EARTH_RADIUS,
        )
        average += dist
    }
    average /= cast(f64)pair_index
    fmt.printfln("Average: %.12f of %d pairs", average, pair_index)
}

expect_token_type :: proc(
    parser: ^Json,
    token_type: JsonTokenType,
) -> (
    JsonToken,
    bool,
) #optional_ok {
    token := json_next(parser)
    if token.type != token_type {
        fmt.eprintfln(
            "Got invalid token %s while expectind %s",
            token.type,
            token_type,
        )
        return token, false
    }
    return token, true
}

Pair :: struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
}

pair_from_json :: proc(parser: ^Json) -> (Pair, bool) {
    pair_field_from_json :: proc(
        parser: ^Json,
        field_name: string,
    ) -> (
        f64,
        bool,
    ) {
        ok: bool = ---
        token: JsonToken = ---
        if token, ok = expect_token_type(parser, .string); !ok do return 0.0, false
        if token.payload != field_name {
            fmt.eprintfln(
                "Got invalid token string %s while expecting %s",
                token.payload,
                field_name,
            )
            return 0.0, false
        }
        if token, ok = expect_token_type(parser, .number); !ok do return 0.0, false
        return strconv.parse_f64(token.payload)

    }
    if _, ok := expect_token_type(parser, .object_start); !ok do return {}, false

    ok: bool = ---
    pair: Pair = ---
    pair.x0, ok = pair_field_from_json(parser, "x0")
    if !ok do return {}, false
    pair.y0, ok = pair_field_from_json(parser, "y0")
    if !ok do return {}, false
    pair.x1, ok = pair_field_from_json(parser, "x1")
    if !ok do return {}, false
    pair.y1, ok = pair_field_from_json(parser, "y1")
    if !ok do return {}, false

    if _, ok := expect_token_type(parser, .object_end); !ok do return {}, false

    return pair, true
}
