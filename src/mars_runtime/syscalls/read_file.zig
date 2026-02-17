const std = @import("std");
const model = @import("model.zig");
const ExecState = model.ExecState;
const Program = model.Program;
const StatusCode = model.StatusCode;

const max_open_file_count = model.max_open_file_count;

pub fn syscall_read_file(parsed: *Program, state: *ExecState) ?i32 {
    const fd = read_reg(state, 4);
    const target_address: u32 = @bitCast(read_reg(state, 5));
    const requested_count = read_reg(state, 6);
    if (requested_count < 0) return -1;

    const open_file = get_open_file(state, fd) orelse return -1;
    const file = &state.virtual_files[open_file.file_index];
    if (!file.in_use) return -1;

    if (open_file.position_bytes > file.len_bytes) return -1;
    const available = file.len_bytes - open_file.position_bytes;
    const request_u32: u32 = @intCast(requested_count);
    const copy_count = @min(request_u32, available);

    // Copy from file contents into simulated memory.
    var i: u32 = 0;
    while (i < copy_count) : (i += 1) {
        const source_index: usize = @intCast(open_file.position_bytes + i);
        if (!write_u8(parsed, target_address + i, file.data[source_index])) return null;
    }

    open_file.position_bytes += copy_count;
    return @intCast(copy_count);
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn write_u8(parsed: *Program, address: u32, value: u8) bool {
    // Simplified - would need access to exec_state and memory functions
    return false;
}

fn get_open_file(state: *ExecState, fd: i32) ?*model.OpenFile {
    if (fd < 3) return null;
    const index_u32: u32 = @intCast(fd - 3);
    if (index_u32 >= max_open_file_count) return null;
    const open_file = &state.open_files[index_u32];
    if (!open_file.in_use) return null;
    return open_file;
}
