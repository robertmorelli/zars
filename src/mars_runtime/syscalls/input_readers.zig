const std = @import("std");

// Input validation and token reading helpers for syscalls

pub fn input_exhausted_for_token(state: anytype) bool {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    return index >= input_text.len;
}

pub fn input_exhausted_at_eof(state: anytype) bool {
    return state.input_offset_bytes >= state.input_text.len;
}

pub fn read_next_input_token(state: anytype) ?[]const u8 {
    // Float/double scanners reuse this token reader.
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    if (index >= input_text.len) return null;

    const start = index;
    while (index < input_text.len and !std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    state.input_offset_bytes = @intCast(index);
    return input_text[start..index];
}

pub fn read_next_input_int(state: anytype) ?i32 {
    // Integer scanner intentionally consumes one numeric token and leaves trailing
    // whitespace/newline for later readers, matching service 5 expectations.
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    if (index >= input_text.len) return null;

    var sign: i64 = 1;
    if (input_text[index] == '-') {
        sign = -1;
        index += 1;
    } else if (input_text[index] == '+') {
        index += 1;
    }

    if (index >= input_text.len) return null;
    if (!std.ascii.isDigit(input_text[index])) return null;

    var value: i64 = 0;
    while (index < input_text.len and std.ascii.isDigit(input_text[index])) : (index += 1) {
        value = value * 10 + (input_text[index] - '0');
    }
    value *= sign;

    if (value < std.math.minInt(i32)) return null;
    if (value > std.math.maxInt(i32)) return null;
    state.input_offset_bytes = @intCast(index);
    return @intCast(value);
}

pub fn read_next_input_float(state: anytype) ?f32 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f32, token) catch null;
}

pub fn read_next_input_double(state: anytype) ?f64 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f64, token) catch null;
}

pub fn read_next_input_char(state: anytype) ?i32 {
    // Char reader consumes exactly one byte, including whitespace/newlines.
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    if (index >= input_text.len) return null;
    const byte = input_text[index];
    index += 1;
    state.input_offset_bytes = @intCast(index);
    return byte;
}
