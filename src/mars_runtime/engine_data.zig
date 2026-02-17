const std = @import("std");
const model = @import("model.zig");
const operand_parse = @import("operand_parse.zig");

const Program = model.Program;
const data_capacity_bytes = model.data_capacity_bytes;

pub fn align_data(parsed: *Program, alignment: u32) !void {
    if (alignment == 0) return;
    const mask: u32 = alignment - 1;
    const aligned = (parsed.data_len_bytes + mask) & ~mask;
    if (aligned > data_capacity_bytes) return error.OutOfBounds;
    while (parsed.data_len_bytes < aligned) {
        parsed.data[parsed.data_len_bytes] = 0;
        parsed.data_len_bytes += 1;
    }
}

pub fn parse_numeric_data_list(parsed: *Program, rest: []const u8, byte_width: u32) bool {
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = std.mem.trim(u8, item_raw, " \t\r\n");
        if (item.len == 0) continue;
        const value = operand_parse.parse_immediate(item) orelse return false;
        if (!append_numeric_value(parsed, value, byte_width)) return false;
    }
    return true;
}

pub fn append_numeric_value(parsed: *Program, value: i32, byte_width: u32) bool {
    if (parsed.data_len_bytes + byte_width > data_capacity_bytes) return false;
    const bits: u32 = @bitCast(value);
    var i: u32 = 0;
    while (i < byte_width) : (i += 1) {
        const shift: u5 = @intCast(i * 8);
        parsed.data[parsed.data_len_bytes] = @intCast((bits >> shift) & 0xFF);
        parsed.data_len_bytes += 1;
    }
    return true;
}

pub fn parse_float_data_list(parsed: *Program, rest: []const u8) bool {
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = std.mem.trim(u8, item_raw, " \t\r\n");
        if (item.len == 0) continue;
        const value = std.fmt.parseFloat(f32, item) catch return false;
        if (!append_u32_be(parsed, @bitCast(value))) return false;
    }
    return true;
}

pub fn parse_double_data_list(parsed: *Program, rest: []const u8) bool {
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = std.mem.trim(u8, item_raw, " \t\r\n");
        if (item.len == 0) continue;
        const value = std.fmt.parseFloat(f64, item) catch return false;
        if (!append_u64_be(parsed, @bitCast(value))) return false;
    }
    return true;
}

pub fn append_u32_be(parsed: *Program, value: u32) bool {
    if (parsed.data_len_bytes + 4 > data_capacity_bytes) return false;
    parsed.data[parsed.data_len_bytes + 0] = @intCast(value & 0xFF);
    parsed.data[parsed.data_len_bytes + 1] = @intCast((value >> 8) & 0xFF);
    parsed.data[parsed.data_len_bytes + 2] = @intCast((value >> 16) & 0xFF);
    parsed.data[parsed.data_len_bytes + 3] = @intCast((value >> 24) & 0xFF);
    parsed.data_len_bytes += 4;
    return true;
}

pub fn append_u64_be(parsed: *Program, value: u64) bool {
    if (parsed.data_len_bytes + 8 > data_capacity_bytes) return false;
    parsed.data[parsed.data_len_bytes + 0] = @intCast(value & 0xFF);
    parsed.data[parsed.data_len_bytes + 1] = @intCast((value >> 8) & 0xFF);
    parsed.data[parsed.data_len_bytes + 2] = @intCast((value >> 16) & 0xFF);
    parsed.data[parsed.data_len_bytes + 3] = @intCast((value >> 24) & 0xFF);
    parsed.data[parsed.data_len_bytes + 4] = @intCast((value >> 32) & 0xFF);
    parsed.data[parsed.data_len_bytes + 5] = @intCast((value >> 40) & 0xFF);
    parsed.data[parsed.data_len_bytes + 6] = @intCast((value >> 48) & 0xFF);
    parsed.data[parsed.data_len_bytes + 7] = @intCast((value >> 56) & 0xFF);
    parsed.data_len_bytes += 8;
    return true;
}
