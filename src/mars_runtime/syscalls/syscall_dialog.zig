const std = @import("std");
const model = @import("model.zig");

const Program = model.Program;
const ExecState = model.ExecState;
const StatusCode = model.StatusCode;

pub fn syscall_headless_dialog_termination(
    state: *ExecState,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    // In this environment, MARS dialog syscalls throw HeadlessException and print:
    // "\nProgram terminated when maximum step limit -1 reached.\n\n"
    const output_format = @import("output_format.zig");
    const status = output_format.append_bytes(
        output,
        output_len_bytes,
        "\nProgram terminated when maximum step limit -1 reached.\n\n",
    );
    if (status != .ok) return status;
    state.halted = true;
    return .ok;
}
