const model = @import("model.zig");
const output_format = @import("output_format.zig");
const StatusCode = model.StatusCode;
const ExecState = model.ExecState;

pub fn syscall_print_binary(state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    const value: u32 = @bitCast(read_reg(state, 4));
    var temp: [32]u8 = undefined;
    var index: usize = 0;
    while (index < temp.len) : (index += 1) {
        const bit_index: u5 = @intCast(31 - index);
        temp[index] = if (((value >> bit_index) & 1) == 1) '1' else '0';
    }
    return output_format.append_bytes(output, output_len_bytes, temp[0..]);
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}
