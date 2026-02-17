// Input parsing and output helpers for the MIPS runtime.
// This module handles reading integers, floats, chars, and strings from input text.

const std = @import("std");
const types = @import("types.zig");
const Program = types.Program;
const ExecState = types.ExecState;
const StatusCode = types.StatusCode;
const memory = @import("memory.zig");
const data_base_addr = types.data_base_addr;

/// Check if all remaining input is whitespace or empty (for token-reading syscalls).
pub fn input_exhausted_for_token(state: *const ExecState) bool {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    return index >= input_text.len;
}

/// Check if input offset is at or past end of input (for byte-level syscalls).
pub fn input_exhausted_at_eof(state: *const ExecState) bool {
    return state.input_offset_bytes >= state.input_text.len;
}

/// Read next integer token from input. Consumes whitespace and one numeric token.
pub fn read_next_input_int(state: *ExecState) ?i32 {
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

/// Read next float token from input.
pub fn read_next_input_float(state: *ExecState) ?f32 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f32, token) catch null;
}

/// Read next double token from input.
pub fn read_next_input_double(state: *ExecState) ?f64 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f64, token) catch null;
}

/// Read next character (single byte) from input.
pub fn read_next_input_char(state: *ExecState) ?i32 {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    if (index >= input_text.len) return null;
    const byte = input_text[index];
    index += 1;
    state.input_offset_bytes = @intCast(index);
    return byte;
}

/// Read next whitespace-delimited token from input.
fn read_next_input_token(state: *ExecState) ?[]const u8 {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    if (index >= input_text.len) return null;

    const start = index;
    while (index < input_text.len and !std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    state.input_offset_bytes = @intCast(index);
    return input_text[start..index];
}

/// Read string from input (syscall 8). Mirrors MARS fgets-like behavior.
pub fn syscall_read_string(
    parsed: *Program,
    state: *ExecState,
    buffer_address: u32,
    length: i32,
) bool {
    var max_length = length - 1;
    var add_null_byte = true;
    if (max_length < 0) {
        max_length = 0;
        add_null_byte = false;
    }

    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    const start = index;
    while (index < input_text.len and input_text[index] != '\n') : (index += 1) {}
    const line_end = index;
    if (index < input_text.len and input_text[index] == '\n') {
        index += 1;
    }
    state.input_offset_bytes = @intCast(index);

    const line = input_text[start..line_end];
    const line_len_i32: i32 = @intCast(line.len);
    var string_length = @min(max_length, line_len_i32);
    if (string_length < 0) string_length = 0;

    var i: i32 = 0;
    while (i < string_length) : (i += 1) {
        const src_index: usize = @intCast(i);
        const dst_address = buffer_address + @as(u32, @intCast(i));
        if (!memory.write_u8(parsed, state, dst_address, line[src_index])) return false;
    }

    if (string_length < max_length) {
        const newline_address = buffer_address + @as(u32, @intCast(string_length));
        if (!memory.write_u8(parsed, state, newline_address, '\n')) return false;
        string_length += 1;
    }

    if (add_null_byte) {
        const null_address = buffer_address + @as(u32, @intCast(string_length));
        if (!memory.write_u8(parsed, state, null_address, 0)) return false;
    }

    return true;
}

/// Read C string from data segment into buffer.
pub fn read_c_string_from_data(
    parsed: *Program,
    state: *ExecState,
    address: u32,
    buffer: *[types.virtual_file_name_capacity_bytes]u8,
) ?[]const u8 {
    var index: u32 = 0;
    while (index < buffer.len) : (index += 1) {
        const ch = memory.read_u8(parsed, state, address + index) orelse return null;
        if (ch == 0) {
            return buffer[0..index];
        }
        buffer[index] = ch;
    }
    return null;
}

/// Append C string from data segment to output buffer (syscall 4).
pub fn append_c_string_from_data(
    parsed: *Program,
    state: *ExecState,
    data_offset: u32,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    if (data_offset >= parsed.data_len_bytes) return .runtime_error;
    var index: u32 = data_offset;
    while (index < parsed.data_len_bytes) : (index += 1) {
        const ch = parsed.data[index];
        if (ch == 0) return .ok;
        const output_len = output_len_bytes.*;
        if (output_len >= output.len) return .runtime_error;
        output[output_len] = ch;
        output_len_bytes.* += 1;
    }
    return .runtime_error;
}
