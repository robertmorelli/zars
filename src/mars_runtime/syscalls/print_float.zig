const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_print_float(state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    const bits = read_fp_single(state, 12);
    const value: f32 = @bitCast(bits);
    return output_format.append_java_float(output, output_len_bytes, value);
}

fn read_fp_single(state: *ExecState, reg: u5) u32 {
    return state.fp_regs[reg];
}
