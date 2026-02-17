const model = @import("model.zig");
const ExecState = model.ExecState;
const Program = model.Program;
const StatusCode = model.StatusCode;

const data_base_addr = model.data_base_addr;

pub fn syscall_print_string(parsed: *Program, state: *ExecState, output: []u8, output_len_bytes: *u32) StatusCode {
    const address: u32 = @bitCast(read_reg(state, 4));
    if (address < data_base_addr) return .runtime_error;
    const data_offset = address - data_base_addr;
    return append_c_string_from_data(parsed, data_offset, output, output_len_bytes);
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn append_c_string_from_data(
    parsed: *Program,
    data_offset: u32,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    // Service 4 prints bytes until a NUL terminator.
    const output_format = @import("output_format.zig");
    if (data_offset >= parsed.data_len_bytes) return .runtime_error;
    var index: u32 = data_offset;
    while (index < parsed.data_len_bytes) : (index += 1) {
        const ch = parsed.data[index];
        if (ch == 0) return .ok;
        const status = output_format.append_bytes(output, output_len_bytes, &[_]u8{ch});
        if (status != .ok) return status;
    }
    return .runtime_error;
}
