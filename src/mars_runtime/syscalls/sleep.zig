const model = @import("model.zig");
const ExecState = model.ExecState;

pub fn syscall_sleep(state: *ExecState) void {
    // Sleep is intentionally modeled as a no-op for deterministic wasm execution.
    _ = read_reg(state, 4);
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}
