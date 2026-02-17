const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_read_float(state: *ExecState) StatusCode {
    const input_readers = @import("input_readers.zig");
    if (input_readers.input_exhausted_for_token(state)) return .needs_input;
    const value = input_readers.read_next_input_float(state) orelse return .runtime_error;
    write_fp_single(state, 0, @bitCast(value));
    return .ok;
}

fn write_fp_single(state: *ExecState, reg: u5, bits: u32) void {
    state.fp_regs[reg] = bits;
}
