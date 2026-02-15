const std = @import("std");
const zars = @import("zars");

const max_program_size = 256 * 1024;
const max_input_size = 64 * 1024;
const max_output_size = 256 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var program_path: ?[]const u8 = null;
    var smc_enabled = false;
    var delayed_branching = false;

    // Parse arguments (skip args[0] which is the program name)
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "smc")) {
            smc_enabled = true;
        } else if (std.mem.eql(u8, arg, "db")) {
            delayed_branching = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage();
            return;
        } else if (arg[0] != '-') {
            program_path = arg;
        }
    }

    if (program_path == null) {
        std.debug.print("Error: No program file specified\n\n", .{});
        try printUsage();
        std.process.exit(1);
    }

    // Read program file
    const program_text = std.fs.cwd().readFileAlloc(allocator, program_path.?, max_program_size) catch |err| {
        std.debug.print("Error reading file '{s}': {}\n", .{ program_path.?, err });
        std.process.exit(1);
    };
    defer allocator.free(program_text);

    // Read stdin
    const stdin = std.fs.File.stdin();
    const input_text = stdin.readToEndAlloc(allocator, max_input_size) catch |err| {
        std.debug.print("Error reading stdin: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(input_text);

    // Run program
    var output_buffer: [max_output_size]u8 = undefined;
    const result = zars.engine.run_program(program_text, &output_buffer, .{
        .smc_enabled = smc_enabled,
        .delayed_branching_enabled = delayed_branching,
        .input_text = input_text,
    });

    // Write output to stdout
    const stdout = std.fs.File.stdout();
    if (result.output_len_bytes > 0) {
        try stdout.writeAll(output_buffer[0..result.output_len_bytes]);
    }

    // Exit with appropriate code
    if (result.status != .ok) {
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const stderr = std.fs.File.stderr();
    try stderr.writeAll(
        \\Usage: zars [options] <program.s>
        \\
        \\Options:
        \\  smc     Enable self-modifying code
        \\  db      Enable delayed branching
        \\  --help  Show this help
        \\
        \\Examples:
        \\  echo "20" | zars smc test_programs/smc.s
        \\  zars program.s < input.txt
        \\
    );
}
