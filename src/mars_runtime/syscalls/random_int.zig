const model = @import("model.zig");
const java_random = @import("java_random.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_random_int(state: *ExecState) StatusCode {
    const stream_id = read_reg(state, 4);
    const random_value = java_random.next_int(state, stream_id) orelse return .runtime_error;
    write_reg(state, 4, random_value);
    return .ok;
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    if (reg == 0) return;
    state.regs[reg] = value;
}
