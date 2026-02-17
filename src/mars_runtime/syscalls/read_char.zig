const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_read_char(state: *ExecState) StatusCode {
    const input_readers = @import("input_readers.zig");
    if (input_readers.input_exhausted_at_eof(state)) return .needs_input;
    const ch = input_readers.read_next_input_char(state) orelse return .runtime_error;
    write_reg(state, 2, ch);
    return .ok;
}

fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    if (reg == 0) return;
    state.regs[reg] = value;
}
