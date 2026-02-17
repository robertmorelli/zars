const std = @import("std");
const model = @import("model.zig");

const Program = model.Program;
const ExecState = model.ExecState;
const OpenFile = model.OpenFile;

const max_open_file_count = model.max_open_file_count;
const virtual_file_name_capacity_bytes = model.virtual_file_name_capacity_bytes;

pub fn syscall_open_file(parsed: *Program, state: *ExecState) i32 {
    // This runtime models files in-memory to keep wasm runs deterministic.
    const filename_address: u32 = @bitCast(read_reg(state, 4));
    const flags = read_reg(state, 5);

    var filename_buffer: [virtual_file_name_capacity_bytes]u8 = undefined;
    const filename = read_c_string_from_data(parsed, filename_address, &filename_buffer) orelse return -1;

    const file_index: u32 = switch (flags) {
        0 => @import("find_virtual_file_by_name.zig").find_virtual_file_by_name(state, filename) orelse return -1,
        1 => @import("open_or_create_virtual_file.zig").open_or_create_virtual_file(state, filename, .truncate) orelse return -1,
        9 => @import("open_or_create_virtual_file.zig").open_or_create_virtual_file(state, filename, .append) orelse return -1,
        else => return -1,
    };

    const position_bytes: u32 = if (flags == 9) state.virtual_files[file_index].len_bytes else 0;
    return allocate_open_file(state, file_index, flags, position_bytes);
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn allocate_open_file(state: *ExecState, file_index: u32, flags: i32, position_bytes: u32) i32 {
    // File descriptor numbering starts at 3 to reserve stdin/stdout/stderr.
    var i: u32 = 0;
    while (i < max_open_file_count) : (i += 1) {
        const open_file = &state.open_files[i];
        if (open_file.in_use) continue;
        open_file.in_use = true;
        open_file.file_index = file_index;
        open_file.flags = flags;
        open_file.position_bytes = position_bytes;
        return @intCast(i + 3);
    }
    return -1;
}

fn read_c_string_from_data(
    parsed: *Program,
    address: u32,
    buffer: *[virtual_file_name_capacity_bytes]u8,
) ?[]const u8 {
    // File names are read from runtime memory as NUL-terminated strings.
    var index: u32 = 0;
    while (index < buffer.len) : (index += 1) {
        const ch = @import("memory.zig").read_u8(parsed, address + index) orelse return null;
        if (ch == 0) {
            return buffer[0..index];
        }
        buffer[index] = ch;
    }
    return null;
}
