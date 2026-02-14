const std = @import("std");

// Mirrors Java int-cast behavior used by MARS cvt.w.* implementations.
pub fn java_float_to_i32_cast(value: f32) i32 {
    if (std.math.isNan(value)) return 0;
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    if (value <= @as(f32, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    return @intFromFloat(value);
}

// Mirrors Java int-cast behavior used by MARS cvt.w.* implementations.
pub fn java_double_to_i32_cast(value: f64) i32 {
    if (std.math.isNan(value)) return 0;
    if (value >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    if (value <= @as(f64, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    return @intFromFloat(value);
}

// MARS floor/ceil/trunc default action for invalid/out-of-range inputs.
pub fn round_word_default_single(value: f32) i32 {
    if (std.math.isNan(value)) return std.math.maxInt(i32);
    if (std.math.isInf(value)) return std.math.maxInt(i32);
    if (value < @as(f32, @floatFromInt(std.math.minInt(i32)))) return std.math.maxInt(i32);
    if (value > @as(f32, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    return @intFromFloat(value);
}

// MARS floor/ceil/trunc default action for invalid/out-of-range inputs.
pub fn round_word_default_double(value: f64) i32 {
    if (std.math.isNan(value)) return std.math.maxInt(i32);
    if (std.math.isInf(value)) return std.math.maxInt(i32);
    if (value < @as(f64, @floatFromInt(std.math.minInt(i32)))) return std.math.maxInt(i32);
    if (value > @as(f64, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    return @intFromFloat(value);
}

// MARS round.w.s behavior: nearest with ties-to-even.
pub fn round_to_nearest_even_single(value: f32) i32 {
    if (std.math.isNan(value)) return std.math.maxInt(i32);
    if (std.math.isInf(value)) return std.math.maxInt(i32);
    if (value < @as(f32, @floatFromInt(std.math.minInt(i32)))) return std.math.maxInt(i32);
    if (value > @as(f32, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);

    var round = @as(i32, @intFromFloat(@floor(@as(f64, value) + 0.5)));
    var above: i32 = 0;
    var below: i32 = 0;
    if (value < 0) {
        above = @intFromFloat(@trunc(value));
        below = above - 1;
    } else {
        below = @intFromFloat(@trunc(value));
        above = below + 1;
    }
    if ((value - @as(f32, @floatFromInt(below))) == (@as(f32, @floatFromInt(above)) - value)) {
        round = if ((above & 1) == 0) above else below;
    }
    return round;
}

// MARS round.w.d behavior: nearest with ties-to-even.
pub fn round_to_nearest_even_double(value: f64) i32 {
    if (std.math.isNan(value)) return std.math.maxInt(i32);
    if (std.math.isInf(value)) return std.math.maxInt(i32);
    if (value < @as(f64, @floatFromInt(std.math.minInt(i32)))) return std.math.maxInt(i32);
    if (value > @as(f64, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);

    var round = @as(i32, @intFromFloat(@floor(value + 0.5)));
    var above: i32 = 0;
    var below: i32 = 0;
    if (value < 0) {
        above = @intFromFloat(@trunc(value));
        below = above - 1;
    } else {
        below = @intFromFloat(@trunc(value));
        above = below + 1;
    }
    if ((value - @as(f64, @floatFromInt(below))) == (@as(f64, @floatFromInt(above)) - value)) {
        round = if ((above & 1) == 0) above else below;
    }
    return round;
}

// Byte helper with same indexing semantics as MARS Binary.getByte().
pub fn int_get_byte(value: u32, byte_index: u2) u8 {
    const byte_index_u32: u32 = byte_index;
    const shift: u5 = @intCast(byte_index_u32 * 8);
    return @intCast((value >> shift) & 0xFF);
}

// Byte helper with same indexing semantics as MARS Binary.setByte().
pub fn int_set_byte(value: u32, byte_index: u2, replacement: u8) u32 {
    const byte_index_u32: u32 = byte_index;
    const shift: u5 = @intCast(byte_index_u32 * 8);
    const clear_mask: u32 = ~(@as(u32, 0xFF) << shift);
    const replacement_bits: u32 = @as(u32, replacement) << shift;
    return (value & clear_mask) | replacement_bits;
}
