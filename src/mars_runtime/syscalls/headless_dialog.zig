const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_headless_dialog(
    state: *ExecState,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    // Dialog services (50-59) in headless command-mode MARS terminate with this message.
    const status = output_format.append_bytes(
        output,
        output_len_bytes,
        "\nProgram terminated when maximum step limit -1 reached.\n\n",
    );
    if (status != .ok) return status;
    state.halted = true;
    return .ok;
}
