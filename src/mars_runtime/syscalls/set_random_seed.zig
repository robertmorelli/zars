const model = @import("model.zig");
const java_random = @import("java_random.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_set_random_seed(state: *ExecState) StatusCode {
    const stream_id = read_reg(state, 4);
    const seed = read_reg(state, 5);
    java_random.set_random_seed(state, stream_id, seed) orelse return .runtime_error;
    return .ok;
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}
