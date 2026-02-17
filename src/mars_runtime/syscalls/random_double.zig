const model = @import("model.zig");
const java_random = @import("java_random.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_random_double(state: *ExecState) StatusCode {
    const stream_id = read_reg(state, 4);
    const random_value = java_random.next_double(state, stream_id);
    write_double_reg(state, 0, random_value);
    return .ok;
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn write_double_reg(state: *ExecState, reg: u5, value: f64) void {
    const bits = @as(u64, @bitCast(value));
    const low = @as(u32, @truncate(bits));
    const high = @as(u32, bits >> 32);
    state.f_regs[reg] = low;
    state.f_regs[reg + 1] = high;
}
