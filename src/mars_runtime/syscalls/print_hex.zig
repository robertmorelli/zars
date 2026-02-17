const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_print_hex(state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    const value: u32 = @bitCast(read_reg(state, 4));
    return output_format.append_formatted(output, output_len_bytes, "0x{x:0>8}", .{value});
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}
