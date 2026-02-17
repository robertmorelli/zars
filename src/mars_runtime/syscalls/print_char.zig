const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_print_char(state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    const a0: u32 = @bitCast(read_reg(state, 4));
    const ch: u8 = @intCast(a0 & 0xFF);
    return output_format.append_bytes(output, output_len_bytes, &[_]u8{ch});
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}
