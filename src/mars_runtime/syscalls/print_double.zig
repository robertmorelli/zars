const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_print_double(state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    const bits = read_fp_double(state, 12);
    const value: f64 = @bitCast(bits);
    return output_format.append_java_double(output, output_len_bytes, value);
}

fn read_fp_double(state: *ExecState, reg: u5) u64 {
    const low_word = @as(u64, state.fp_regs[reg]);
    const high_word = @as(u64, state.fp_regs[reg + 1]);
    return (high_word << 32) | low_word;
}
