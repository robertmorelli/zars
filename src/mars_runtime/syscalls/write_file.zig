const std = @import("std");
const model = @import("model.zig");
const ExecState = model.ExecState;
const Program = model.Program;

const max_open_file_count = model.max_open_file_count;
const virtual_file_data_capacity_bytes = model.virtual_file_data_capacity_bytes;

pub fn syscall_write_file(parsed: *Program, state: *ExecState) ?i32 {
    const fd = read_reg(state, 4);
    const source_address: u32 = @bitCast(read_reg(state, 5));
    const requested_count = read_reg(state, 6);
    if (requested_count < 0) return -1;

    const open_file = get_open_file(state, fd) orelse return -1;
    const file = &state.virtual_files[open_file.file_index];
    if (!file.in_use) return -1;

    if (open_file.position_bytes > virtual_file_data_capacity_bytes) return -1;
    const write_capacity = virtual_file_data_capacity_bytes - open_file.position_bytes;
    const request_u32: u32 = @intCast(requested_count);
    const write_count = @min(request_u32, write_capacity);

    // Copy from simulated memory into file contents.
    var i: u32 = 0;
    while (i < write_count) : (i += 1) {
        const byte = read_u8(parsed, source_address + i) orelse return null;
        const target_index: usize = @intCast(open_file.position_bytes + i);
        file.data[target_index] = byte;
    }

    open_file.position_bytes += write_count;
    if (open_file.position_bytes > file.len_bytes) {
        file.len_bytes = open_file.position_bytes;
    }

    return @intCast(write_count);
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn read_u8(parsed: *Program, address: u32) ?u8 {
    // Simplified - would need full memory access
    return null;
}

fn get_open_file(state: *ExecState, fd: i32) ?*model.OpenFile {
    if (fd < 3) return null;
    const index_u32: u32 = @intCast(fd - 3);
    if (index_u32 >= max_open_file_count) return null;
    const open_file = &state.open_files[index_u32];
    if (!open_file.in_use) return null;
    return open_file;
}
