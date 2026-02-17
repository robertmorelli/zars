const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_midi_out(state: *ExecState) StatusCode {
    // MidiOut: command-mode behavior does not affect architectural state.
    // We still sanitize inputs so invalid ranges follow MARS fallback defaults.
    const time_audio = @import("time_and_audio.zig");
    _ = time_audio.sanitize_midi_parameter(read_reg(state, 4), 60);
    _ = time_audio.sanitize_midi_duration(read_reg(state, 5), 1000);
    _ = time_audio.sanitize_midi_parameter(read_reg(state, 6), 0);
    _ = time_audio.sanitize_midi_parameter(read_reg(state, 7), 100);
    return .ok;
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}
