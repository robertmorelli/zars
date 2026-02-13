const std = @import("std");
const assert = std.debug.assert;

// Port seed: mirrors key constants from MARS mars/Globals.java.
pub const version = "4.6";
pub const copyright_years = "2003-2014";
pub const copyright_holders = "Pete Sanderson and Kenneth Vollmar";

pub const maximum_message_characters: u32 = 1_000_000;
pub const maximum_error_messages: u32 = 200;
pub const maximum_backsteps: u32 = 1_000;

pub const ascii_non_print = ".";

pub fn validate_invariants() void {
    assert(maximum_message_characters > 0);
    assert(maximum_error_messages > 0);
    assert(maximum_backsteps > 0);
}

test "globals invariants" {
    validate_invariants();
    try std.testing.expectEqualStrings("4.6", version);
}
