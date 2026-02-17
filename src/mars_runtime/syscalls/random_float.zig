const model = @import("model.zig");
const java_random = @import("java_random.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_random_float(state: *ExecState) StatusCode {
    const stream_id = read_reg(state, 4);
    const random_value = java_random.next_float(state, stream_id);
    write_float_reg(state, 0, random_value);
    return .ok;
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn write_float_reg(state: *ExecState, reg: u5, value: f32) void {
    const bits = @as(u32, @bitCast(value));
    state.f_regs[reg] = bits;
}
