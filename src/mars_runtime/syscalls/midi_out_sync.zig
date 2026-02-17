const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_midi_out_sync(state: *ExecState) StatusCode {
    // MidiOutSync mirrors MidiOut state semantics in command-mode parity tests.
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
