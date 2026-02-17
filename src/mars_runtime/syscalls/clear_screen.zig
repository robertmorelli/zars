const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_clear_screen(state: *ExecState) StatusCode {
    // MARS extension: clear screen. Command-mode behavior is effectively no-op.
    _ = state;
    return .ok;
}
