const model = @import("model.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_time(state: *ExecState) void {
    // Service 30 writes current wall-clock milliseconds split across $a0/$a1.
    const time_audio = @import("time_and_audio.zig");
    const millis_bits = time_audio.current_time_millis_bits();
    const low_word: u32 = @truncate(millis_bits);
    const high_word: u32 = @truncate(millis_bits >> 32);
    write_reg(state, 4, @bitCast(low_word));
    write_reg(state, 5, @bitCast(high_word));
}

fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    if (reg == 0) return;
    state.regs[reg] = value;
}
