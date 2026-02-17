// Syscall dispatch: routes MARS syscall services (v0 = 1..60) to handlers.
// All helpers are accessed through inst_util.zig.

const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(
    parsed: *u.Program,
    state: *u.ExecState,
    output: []u8,
    output_len_bytes: *u32,
) u.StatusCode {
    const v0 = u.read_reg(state, 2);

    if (v0 == 1) {
        const value = u.read_reg(state, 4);
        return u.output_format.append_formatted(output, output_len_bytes, "{}", .{value});
    }

    if (v0 == 2) {
        const bits = u.read_fp_single(state, 12);
        const value: f32 = @bitCast(bits);
        return u.output_format.append_java_float(output, output_len_bytes, value);
    }

    if (v0 == 3) {
        const bits = u.read_fp_double(state, 12);
        const value: f64 = @bitCast(bits);
        return u.output_format.append_java_double(output, output_len_bytes, value);
    }

    if (v0 == 4) {
        const address: u32 = @bitCast(u.read_reg(state, 4));
        if (address < u.data_base_addr) return .runtime_error;
        const data_offset = address - u.data_base_addr;
        return u.append_c_string_from_data(parsed, state, data_offset, output, output_len_bytes);
    }

    if (v0 == 5) {
        if (u.input_exhausted_for_token(state)) return .needs_input;
        const value = u.read_next_input_int(state) orelse return .runtime_error;
        u.write_reg(state, 2, value);
        return .ok;
    }

    if (v0 == 6) {
        if (u.input_exhausted_for_token(state)) return .needs_input;
        const value = u.read_next_input_float(state) orelse return .runtime_error;
        u.write_fp_single(state, 0, @bitCast(value));
        return .ok;
    }

    if (v0 == 7) {
        if (u.input_exhausted_for_token(state)) return .needs_input;
        const value = u.read_next_input_double(state) orelse return .runtime_error;
        u.write_fp_double(state, 0, @bitCast(value));
        return .ok;
    }

    if (v0 == 8) {
        if (u.input_exhausted_at_eof(state)) return .needs_input;
        const buffer_address: u32 = @bitCast(u.read_reg(state, 4));
        const length = u.read_reg(state, 5);
        if (!u.syscall_read_string(parsed, state, buffer_address, length)) return .runtime_error;
        return .ok;
    }

    if (v0 == 9) {
        const allocation_size = u.read_reg(state, 4);
        const allocation_address = u.syscall_sbrk(state, allocation_size) orelse return .runtime_error;
        u.write_reg(state, 2, @bitCast(allocation_address));
        return .ok;
    }

    if (v0 == 10) {
        // Command-line MARS appends newline on exit service.
        const newline_status = u.output_format.append_bytes(output, output_len_bytes, "\n");
        if (newline_status != .ok) return newline_status;
        state.halted = true;
        return .ok;
    }

    if (v0 == 11) {
        const a0: u32 = @bitCast(u.read_reg(state, 4));
        const ch: u8 = @intCast(a0 & 0xFF);
        return u.output_format.append_bytes(output, output_len_bytes, &[_]u8{ch});
    }

    if (v0 == 12) {
        if (u.input_exhausted_at_eof(state)) return .needs_input;
        const ch = u.read_next_input_char(state) orelse return .runtime_error;
        u.write_reg(state, 2, ch);
        return .ok;
    }

    if (v0 == 13) {
        const fd = u.syscall_open_file(parsed, state);
        u.write_reg(state, 2, fd);
        return .ok;
    }

    if (v0 == 14) {
        const count = u.syscall_read_file(parsed, state) orelse return .runtime_error;
        u.write_reg(state, 2, count);
        return .ok;
    }

    if (v0 == 15) {
        const count = u.syscall_write_file(parsed, state) orelse return .runtime_error;
        u.write_reg(state, 2, count);
        return .ok;
    }

    if (v0 == 16) {
        if (!u.syscall_close_file(state)) return .runtime_error;
        return .ok;
    }

    if (v0 == 17) {
        // Exit2 uses $a0 as process exit code in MARS command mode.
        const newline_status = u.output_format.append_bytes(output, output_len_bytes, "\n");
        if (newline_status != .ok) return newline_status;
        state.halted = true;
        return .ok;
    }

    if (v0 == 30) {
        const millis_bits = u.current_time_millis_bits();
        const low_word: u32 = @truncate(millis_bits);
        const high_word: u32 = @truncate(millis_bits >> 32);
        u.write_reg(state, 4, @bitCast(low_word));
        u.write_reg(state, 5, @bitCast(high_word));
        return .ok;
    }

    if (v0 == 31) {
        _ = u.sanitize_midi_parameter(u.read_reg(state, 4), 60);
        _ = u.sanitize_midi_duration(u.read_reg(state, 5), 1000);
        _ = u.sanitize_midi_parameter(u.read_reg(state, 6), 0);
        _ = u.sanitize_midi_parameter(u.read_reg(state, 7), 100);
        return .ok;
    }

    if (v0 == 32) {
        _ = u.read_reg(state, 4);
        return .ok;
    }

    if (v0 == 33) {
        _ = u.sanitize_midi_parameter(u.read_reg(state, 4), 60);
        _ = u.sanitize_midi_duration(u.read_reg(state, 5), 1000);
        _ = u.sanitize_midi_parameter(u.read_reg(state, 6), 0);
        _ = u.sanitize_midi_parameter(u.read_reg(state, 7), 100);
        return .ok;
    }

    if (v0 == 34) {
        const value: u32 = @bitCast(u.read_reg(state, 4));
        return u.output_format.append_formatted(output, output_len_bytes, "0x{x:0>8}", .{value});
    }

    if (v0 == 35) {
        const value: u32 = @bitCast(u.read_reg(state, 4));
        var temp: [32]u8 = undefined;
        var index: usize = 0;
        while (index < temp.len) : (index += 1) {
            const bit_index: u5 = @intCast(31 - index);
            temp[index] = if (((value >> bit_index) & 1) == 1) '1' else '0';
        }
        return u.output_format.append_bytes(output, output_len_bytes, temp[0..]);
    }

    if (v0 == 36) {
        const value: u32 = @bitCast(u.read_reg(state, 4));
        return u.output_format.append_formatted(output, output_len_bytes, "{}", .{value});
    }

    if (v0 == 40) {
        const stream_id = u.read_reg(state, 4);
        const seed = u.read_reg(state, 5);
        u.java_random.set_random_seed(state, stream_id, seed) orelse return .runtime_error;
        return .ok;
    }

    if (v0 == 41) {
        const stream_id = u.read_reg(state, 4);
        const random_value = u.java_random.next_int(state, stream_id) orelse return .runtime_error;
        u.write_reg(state, 4, random_value);
        return .ok;
    }

    if (v0 == 42) {
        const stream_id = u.read_reg(state, 4);
        const bound = u.read_reg(state, 5);
        const random_value = u.java_random.next_int_bound(state, stream_id, bound) orelse return .runtime_error;
        u.write_reg(state, 4, random_value);
        return .ok;
    }

    if (v0 == 43) {
        const stream_id = u.read_reg(state, 4);
        const random_value = u.java_random.next_float(state, stream_id) orelse return .runtime_error;
        u.write_fp_single(state, 0, @bitCast(random_value));
        return .ok;
    }

    if (v0 == 44) {
        const stream_id = u.read_reg(state, 4);
        const random_value = u.java_random.next_double(state, stream_id) orelse return .runtime_error;
        u.write_fp_double(state, 0, @bitCast(random_value));
        return .ok;
    }

    if (v0 == 50 or v0 == 51 or v0 == 52 or v0 == 53 or v0 == 54 or
        v0 == 55 or v0 == 56 or v0 == 57 or v0 == 58 or v0 == 59)
    {
        return u.syscall_headless_dialog_termination(state, output, output_len_bytes);
    }

    if (v0 == 60) {
        return .ok;
    }

    return .runtime_error;
}
