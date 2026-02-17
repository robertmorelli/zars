const std = @import("std");
const model = @import("model.zig");

const ExecState = model.ExecState;
const OpenFile = model.OpenFile;
const VirtualFile = model.VirtualFile;

const max_open_file_count = model.max_open_file_count;
const max_virtual_file_count = model.max_virtual_file_count;
const virtual_file_name_capacity_bytes = model.virtual_file_name_capacity_bytes;

pub fn find_virtual_file_by_name(state: *ExecState, name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < max_virtual_file_count) : (i += 1) {
        const file = &state.virtual_files[i];
        if (!file.in_use) continue;
        const existing_name = file.name[0..file.name_len_bytes];
        if (std.mem.eql(u8, existing_name, name)) {
            return i;
        }
    }
    return null;
}
