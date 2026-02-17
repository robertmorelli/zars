const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_read_double(state: *ExecState) StatusCode {
    const input_readers = @import("input_readers.zig");
    if (input_readers.input_exhausted_for_token(state)) return .needs_input;
    const value = input_readers.read_next_input_double(state) orelse return .runtime_error;
    write_fp_double(state, 0, @bitCast(value));
    return .ok;
}

fn write_fp_double(state: *ExecState, reg: u5, bits: u64) void {
    state.fp_regs[reg] = @intCast(bits & 0xFFFF_FFFF);
    state.fp_regs[reg + 1] = @intCast((bits >> 32) & 0xFFFF_FFFF);
}
