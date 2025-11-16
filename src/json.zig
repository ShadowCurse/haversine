const std = @import("std");

buffer: []const u8,

const Self = @This();

pub const TokenType = enum {
    object_start,
    object_end,
    buffer_end,
    array_start,
    array_end,
    string,
    number,
};

pub const Token = union(TokenType) {
    object_start: void,
    object_end: void,
    buffer_end: void,
    array_start: void,
    array_end: void,
    string: []const u8,
    number: []const u8,
};

pub fn init(buffer: []const u8) Self {
    return .{ .buffer = buffer };
}

pub fn next(self: *Self) ?Token {
    self.skip_not_usefull();
    if (self.buffer.len == 0) return null;
    switch (self.buffer[0]) {
        '{' => {
            self.buffer = self.buffer[1..];
            return .object_start;
        },
        '}' => {
            self.buffer = self.buffer[1..];
            if (self.buffer.len == 0) return .buffer_end;
            return .object_end;
        },
        '[' => {
            self.buffer = self.buffer[1..];
            return .array_start;
        },
        ']' => {
            self.buffer = self.buffer[1..];
            return .array_end;
        },
        '"' => {
            var string_end_index: u32 = 1;
            // TODO skip escaped \" symbols
            while (self.buffer[string_end_index] != '"' and string_end_index < self.buffer.len)
                string_end_index += 1;
            const token: Token = .{ .string = self.buffer[1..string_end_index] };
            self.buffer = self.buffer[string_end_index + 1 ..];
            return token;
        },
        // number
        else => {
            var number_end_index: u32 = 1;
            while (std.ascii.isDigit(self.buffer[number_end_index]) or
                self.buffer[number_end_index] == '-' or
                self.buffer[number_end_index] == '.')
                number_end_index += 1;
            const token: Token = .{ .number = self.buffer[0..number_end_index] };
            self.buffer = self.buffer[number_end_index + 1 ..];
            return token;
        },
    }
}

pub fn peek_array_end(self: *Self) bool {
    self.skip_not_usefull();
    if (self.buffer.len == 0) return false;
    return self.buffer[0] == ']';
}

fn skip_not_usefull(self: *Self) void {
    if (self.buffer.len == 0) return;
    while (std.ascii.isWhitespace(self.buffer[0]) or
        self.buffer[0] == ':' or
        self.buffer[0] == ',')
    {
        self.buffer = self.buffer[1..];
        if (self.buffer.len == 0) return;
    }
}

