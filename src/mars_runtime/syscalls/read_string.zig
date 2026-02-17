const std = @import("std");
const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;
const Program = model.Program;

const virtual_file_name_capacity_bytes = model.virtual_file_name_capacity_bytes;

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

    // Mirrors MARS fgets-like behavior: consume one line and add newline if room remains.
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
        if (!write_u8(parsed, dst_address, line[src_index])) return false;
    }

    if (string_length < max_length) {
        const newline_address = buffer_address + @as(u32, @intCast(string_length));
        if (!write_u8(parsed, newline_address, '\n')) return false;
        string_length += 1;
    }

    if (add_null_byte) {
        const null_address = buffer_address + @as(u32, @intCast(string_length));
        if (!write_u8(parsed, null_address, 0)) return false;
    }

    return true;
}

fn write_u8(parsed: *Program, address: u32, value: u8) bool {
    const data_address_to_offset = @import("memory.zig").data_address_to_offset;
    const heap_address_to_offset = @import("memory.zig").heap_address_to_offset;

    if (data_address_to_offset(parsed, address)) |offset| {
        parsed.data[offset] = value;
        return true;
    }
    if (heap_address_to_offset(address)) |offset| {
        // Need access to exec_state_storage
        return false;  // Simplified for now
    }
    return false;
}
