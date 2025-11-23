package processor

import "core:unicode"

Json :: struct {
    buffer: []u8,
}

// ObjectStart :: struct {}
// ObjectEnd :: struct {}
// BufferEnd :: struct {}
// ArrayStart :: struct {}
// ArrayEnd :: struct {}
// String :: distinct string
// Number :: distinct string
//
// JsonToken :: union {
//     ObjectStart,
//     ObjectEnd,
//     BufferEnd,
//     ArrayStart,
//     ArrayEnd,
//     String,
//     Number,
// }

JsonTokenType :: enum {
    object_start,
    object_end,
    buffer_end,
    array_start,
    array_end,
    string,
    number,
}

JsonToken :: struct {
    type:    JsonTokenType,
    payload: string,
}

json_init :: proc(buffer: []u8) -> Json {
    return {buffer = buffer}
}

json_next :: proc(json: ^Json) -> JsonToken {
    json_skip_not_usefull(json)
    if len(json.buffer) == 0 do return {.buffer_end, {}}
    switch json.buffer[0] {
    case '{':
        json.buffer = json.buffer[1:]
        return {.object_start, {}}
    case '}':
        json.buffer = json.buffer[1:]
        if len(json.buffer) == 0 do return {.buffer_end, {}}
        return {.object_end, {}}
    case '[':
        json.buffer = json.buffer[1:]
        return {.array_start, {}}
    case ']':
        json.buffer = json.buffer[1:]
        return {.array_end, {}}
    case '"':
        string_end_index: int = 1
        for json.buffer[string_end_index] != '"' && string_end_index < len(json.buffer) {
            string_end_index += 1
        }
        token: JsonToken = {.string, string(json.buffer[1:string_end_index])}
        json.buffer = json.buffer[string_end_index + 1:]
        return token
    //number
    case:
        number_end_index: u32 = 1
        for unicode.is_digit(rune(json.buffer[number_end_index])) ||
            json.buffer[number_end_index] == '-' ||
            json.buffer[number_end_index] == '.' {
            number_end_index += 1
        }
        token: JsonToken = {.number, string(json.buffer[0:number_end_index])}
        json.buffer = json.buffer[number_end_index + 1:]
        return token
    }
}

json_peek_array_end :: proc(json: ^Json) -> bool {
    json_skip_not_usefull(json)
    if len(json.buffer) == 0 do return false
    return json.buffer[0] == ']'
}

@(private = "file")
json_skip_not_usefull :: proc(json: ^Json) {
    for {
        if len(json.buffer) == 0 do return
        c := json.buffer[0]
        if unicode.is_space(rune(c)) || c == ':' || c == ',' do json.buffer = json.buffer[1:]
        else do return
    }

}
