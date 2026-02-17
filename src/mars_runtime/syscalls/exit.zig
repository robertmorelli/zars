const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_exit(state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    // Command-line MARS appends newline on exit service.
    const newline_status = output_format.append_bytes(output, output_len_bytes, "\n");
    if (newline_status != .ok) return newline_status;
    state.halted = true;
    return .ok;
}
