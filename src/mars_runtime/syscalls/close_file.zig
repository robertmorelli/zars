const model = @import("model.zig");
const ExecState = model.ExecState;

const max_open_file_count = model.max_open_file_count;

pub fn syscall_close_file(state: *ExecState) bool {
    const fd = read_reg(state, 4);
    const open_file = get_open_file(state, fd) orelse return false;
    open_file.in_use = false;
    open_file.file_index = 0;
    open_file.position_bytes = 0;
    open_file.flags = 0;
    return true;
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn get_open_file(state: *ExecState, fd: i32) ?*model.OpenFile {
    if (fd < 3) return null;
    const index_u32: u32 = @intCast(fd - 3);
    if (index_u32 >= max_open_file_count) return null;
    const open_file = &state.open_files[index_u32];
    if (!open_file.in_use) return null;
    return open_file;
}
