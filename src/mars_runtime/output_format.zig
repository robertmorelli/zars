const std = @import("std");
const model = @import("model.zig");

const StatusCode = model.StatusCode;

pub fn append_formatted(
    output: []u8,
    output_len_bytes: *u32,
    comptime fmt: []const u8,
    args: anytype,
) StatusCode {
    var temp: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&temp, fmt, args) catch return .runtime_error;
    return append_bytes(output, output_len_bytes, text);
}

pub fn append_java_float(output: []u8, output_len_bytes: *u32, value: f32) StatusCode {
    var temp: [128]u8 = undefined;
    const raw = std.fmt.bufPrint(&temp, "{}", .{value}) catch return .runtime_error;
    return append_java_float_like_text(output, output_len_bytes, raw);
}

pub fn append_java_double(output: []u8, output_len_bytes: *u32, value: f64) StatusCode {
    var temp: [128]u8 = undefined;
    const raw = std.fmt.bufPrint(&temp, "{}", .{value}) catch return .runtime_error;
    return append_java_float_like_text(output, output_len_bytes, raw);
}

fn append_java_float_like_text(
    output: []u8,
    output_len_bytes: *u32,
    raw: []const u8,
) StatusCode {
    // Java-style printFloat/printDouble emit trailing ".0" for integer-looking values.
    const has_decimal = std.mem.indexOfScalar(u8, raw, '.') != null;
    const has_exponent = std.mem.indexOfScalar(u8, raw, 'e') != null or
        std.mem.indexOfScalar(u8, raw, 'E') != null;
    if (has_decimal or has_exponent) {
        return append_bytes(output, output_len_bytes, raw);
    }
    if (std.mem.eql(u8, raw, "nan")) return append_bytes(output, output_len_bytes, raw);
    if (std.mem.eql(u8, raw, "inf")) return append_bytes(output, output_len_bytes, raw);
    if (std.mem.eql(u8, raw, "-inf")) return append_bytes(output, output_len_bytes, raw);
    return append_formatted(output, output_len_bytes, "{s}.0", .{raw});
}

pub fn append_bytes(output: []u8, output_len_bytes: *u32, text: []const u8) StatusCode {
    // Output is a fixed buffer, so every append is bounds-checked.
    const start: u32 = output_len_bytes.*;
    const end: u32 = start + @as(u32, @intCast(text.len));
    if (end > output.len) return .runtime_error;

    const start_index: usize = @intCast(start);
    const end_index: usize = @intCast(end);
    std.mem.copyForwards(u8, output[start_index..end_index], text);
    output_len_bytes.* = end;
    return .ok;
}
