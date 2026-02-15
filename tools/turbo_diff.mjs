#!/usr/bin/env node

/**
 * Turbo Diff Checker - Step-by-step comparison of zars vs MARS
 *
 * Compares execution state after each instruction between zars and MARS.
 * Note: MARS step limits only work for values >= 32 (lower values are
 * interpreted as register names), so we compare at every step from 32 onward.
 */

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const script_dir = path.dirname(fileURLToPath(import.meta.url));
const repo_root = path.resolve(script_dir, "..");
const default_wasm_path = path.join(repo_root, "zig-out/bin/lib/zars_runtime.wasm");
const default_mars_jar_path = path.join(repo_root, "MARS/Mars.jar");

const text_encoder = new TextEncoder();
const text_decoder = new TextDecoder();

// All 32 integer registers by name (for MARS CLI)
const all_register_names = [
    "zero", "at", "v0", "v1", "a0", "a1", "a2", "a3",
    "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
    "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7",
    "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"
];

// All registers to compare (now includes $gp, $sp since zars initializes them correctly)
const compare_register_specs = [
    { name: "zero", index: 0 },
    { name: "at", index: 1 },
    { name: "v0", index: 2 },
    { name: "v1", index: 3 },
    { name: "a0", index: 4 },
    { name: "a1", index: 5 },
    { name: "a2", index: 6 },
    { name: "a3", index: 7 },
    { name: "t0", index: 8 },
    { name: "t1", index: 9 },
    { name: "t2", index: 10 },
    { name: "t3", index: 11 },
    { name: "t4", index: 12 },
    { name: "t5", index: 13 },
    { name: "t6", index: 14 },
    { name: "t7", index: 15 },
    { name: "s0", index: 16 },
    { name: "s1", index: 17 },
    { name: "s2", index: 18 },
    { name: "s3", index: 19 },
    { name: "s4", index: 20 },
    { name: "s5", index: 21 },
    { name: "s6", index: 22 },
    { name: "s7", index: 23 },
    { name: "t8", index: 24 },
    { name: "t9", index: 25 },
    { name: "k0", index: 26 },
    { name: "k1", index: 27 },
    { name: "gp", index: 28 },
    { name: "sp", index: 29 },
    { name: "fp", index: 30 },
    { name: "ra", index: 31 },
];
const compare_register_names = compare_register_specs.map(r => r.name);

function parse_args(argv) {
    const options = {
        program_path: null,
        wasm_path: default_wasm_path,
        mars_jar_path: default_mars_jar_path,
        delayed_branching: false,
        smc: false,
        verbose: false,
        start_step: 32,  // MARS can only use step limits >= 32
    };

    let i = 0;
    while (i < argv.length) {
        const arg = argv[i];
        if (arg === "--wasm") {
            options.wasm_path = argv[++i];
        } else if (arg === "--mars-jar") {
            options.mars_jar_path = argv[++i];
        } else if (arg === "--db") {
            options.delayed_branching = true;
        } else if (arg === "--smc") {
            options.smc = true;
        } else if (arg === "-v" || arg === "--verbose") {
            options.verbose = true;
        } else if (arg === "--start-step") {
            options.start_step = parseInt(argv[++i], 10);
        } else if (arg === "--help" || arg === "-h") {
            print_help();
            process.exit(0);
        } else if (!arg.startsWith("-")) {
            options.program_path = arg;
        }
        i++;
    }

    if (!options.program_path) {
        console.error("Error: No program file specified");
        print_help();
        process.exit(1);
    }

    return options;
}

function print_help() {
    console.log(`
Turbo Diff Checker - Step-by-step zars vs MARS comparison

Usage: node tools/turbo_diff.mjs [options] <program.s>

Options:
  --db              Enable delayed branching
  --smc             Enable self-modifying code
  --wasm <path>     WASM runtime path (default: zig-out/bin/lib/zars_runtime.wasm)
  --mars-jar <path> MARS jar path (default: MARS/Mars.jar)
  --start-step <n>  Start comparing at step n (default: 32, minimum: 32)
  -v, --verbose     Show state at each step
  -h, --help        Show this help

Note: MARS CLI interprets numbers 0-31 as register names, so step-by-step
comparison starts at step 32 by default.
`);
}

function build_wasm() {
    const result = spawnSync("zig", ["build", "wasm-runtime"], {
        cwd: repo_root,
        encoding: "utf8",
    });
    if (result.status !== 0) {
        console.error("Failed to build WASM runtime:");
        console.error(result.stderr);
        process.exit(1);
    }
}

async function load_wasm(wasm_path) {
    const wasm_bytes = fs.readFileSync(wasm_path);
    const module = await WebAssembly.instantiate(wasm_bytes, {});
    return module.instance.exports;
}

function run_mars_at_step(program_path, step_limit, mars_jar_path, mars_options) {
    const args = [
        "-jar", mars_jar_path,
        "sm", "nc",
        step_limit.toString(),
        ...compare_register_names,
        ...mars_options,
        program_path
    ];

    const result = spawnSync("java", args, {
        cwd: repo_root,
        encoding: "utf8",
    });

    // Parse register values from output
    const regs = new Map();
    const lines = (result.stdout || "").split("\n");
    for (const line of lines) {
        const match = line.match(/^\$(\w+)\s+0x([0-9a-fA-F]+)/);
        if (match) {
            const name = match[1];
            const value = parseInt(match[2], 16) >>> 0;
            regs.set(name, value);
        }
    }

    const halted = !result.stdout.includes("maximum step limit");

    return { regs, halted, stdout: result.stdout, stderr: result.stderr };
}

function get_mars_instruction_count(program_path, mars_jar_path, mars_options) {
    const args = [
        "-jar", mars_jar_path,
        "sm", "nc", "ic",
        ...mars_options,
        program_path
    ];

    const result = spawnSync("java", args, {
        cwd: repo_root,
        encoding: "utf8",
    });

    // The instruction count is the last line of output
    const lines = (result.stdout || "").trim().split("\n");
    const last_line = lines[lines.length - 1];
    const count = parseInt(last_line, 10);
    return isNaN(count) ? 0 : count;
}

function setup_zars(wasm, program_text, options) {
    const program_bytes = text_encoder.encode(program_text);

    wasm.zars_reset();
    wasm.zars_set_delayed_branching(options.delayed_branching ? 1 : 0);
    wasm.zars_set_smc_enabled(options.smc ? 1 : 0);

    const memory = wasm.memory;
    const program_ptr = wasm.zars_program_ptr();
    const program_view = new Uint8Array(memory.buffer, program_ptr, program_bytes.length);
    program_view.set(program_bytes);

    const load_status = wasm.zars_load_program(program_bytes.length);
    if (load_status !== 0) {
        throw new Error(`Failed to load program: status ${load_status}`);
    }

    const start_status = wasm.zars_start();
    if (start_status !== 0) {
        throw new Error(`Failed to start program: status ${start_status}`);
    }

    return wasm.zars_instruction_count();
}

function get_zars_registers(wasm) {
    const memory = wasm.memory;
    const regs_ptr = wasm.zars_regs_ptr();
    const regs_view = new Int32Array(memory.buffer, regs_ptr, 32);

    const regs = new Map();
    for (const spec of compare_register_specs) {
        regs.set(spec.name, regs_view[spec.index] >>> 0);
    }
    return regs;
}

function step_zars(wasm) {
    const status = wasm.zars_step();
    // 0 = ok, 4 = halted, 5 = error
    return { status, halted: status === 4, error: status === 5 };
}

function compare_registers(zars_regs, mars_regs) {
    const mismatches = [];
    for (const name of compare_register_names) {
        const zars_val = zars_regs.get(name);
        const mars_val = mars_regs.get(name);
        if (mars_val !== undefined && zars_val !== mars_val) {
            mismatches.push({
                name,
                zars: zars_val,
                mars: mars_val
            });
        }
    }
    return mismatches;
}

function format_hex(value) {
    return "0x" + (value >>> 0).toString(16).padStart(8, "0");
}

async function main() {
    const options = parse_args(process.argv.slice(2));

    console.log(`Turbo Diff: ${options.program_path}`);
    console.log(`Building WASM runtime...`);
    build_wasm();

    const wasm = await load_wasm(options.wasm_path);
    const program_text = fs.readFileSync(path.resolve(repo_root, options.program_path), "utf8");

    const mars_options = [];
    if (options.delayed_branching) mars_options.push("db");
    if (options.smc) mars_options.push("smc");

    // Get total instruction count from MARS
    const total_steps = get_mars_instruction_count(
        path.resolve(repo_root, options.program_path),
        options.mars_jar_path,
        mars_options
    );
    console.log(`Total instructions: ${total_steps}`);

    if (total_steps === 0) {
        console.error("Failed to get instruction count from MARS");
        process.exit(1);
    }

    // Initialize zars
    const zars_instruction_count = setup_zars(wasm, program_text, options);
    console.log(`zars instruction count: ${zars_instruction_count}`);

    // Step through execution
    let current_step = 0;
    let first_mismatch_step = null;

    while (current_step < total_steps) {
        const step_result = step_zars(wasm);
        current_step++;

        if (step_result.error) {
            console.log(`\nzars error at step ${current_step}`);
            break;
        }

        // Only compare at steps >= 32 (MARS limitation)
        if (current_step >= options.start_step) {
            const zars_regs = get_zars_registers(wasm);
            const mars_result = run_mars_at_step(
                path.resolve(repo_root, options.program_path),
                current_step,
                options.mars_jar_path,
                mars_options
            );

            const mismatches = compare_registers(zars_regs, mars_result.regs);

            if (options.verbose) {
                process.stdout.write(`\rStep ${current_step}/${total_steps}: `);
                if (mismatches.length === 0) {
                    process.stdout.write("OK");
                } else {
                    process.stdout.write(`${mismatches.length} mismatches`);
                }
            }

            if (mismatches.length > 0 && first_mismatch_step === null) {
                first_mismatch_step = current_step;
                console.log(`\n\nFIRST MISMATCH at step ${current_step}:`);
                for (const m of mismatches) {
                    console.log(`  $${m.name}: zars=${format_hex(m.zars)} mars=${format_hex(m.mars)}`);
                }

                // Show context: surrounding register state
                console.log(`\nFull register state at step ${current_step}:`);
                console.log("Register       zars            mars");
                console.log("-".repeat(45));
                for (const name of compare_register_names) {
                    const z = zars_regs.get(name);
                    const m = mars_result.regs.get(name);
                    const marker = z !== m ? " <-- MISMATCH" : "";
                    console.log(`$${name.padEnd(6)} ${format_hex(z)}      ${format_hex(m || 0)}${marker}`);
                }
                break;
            }
        }

        if (step_result.halted) {
            if (options.verbose) {
                console.log(`\nzars halted at step ${current_step}`);
            }
            break;
        }
    }

    if (first_mismatch_step === null) {
        console.log(`\n\nSUCCESS: All ${Math.min(current_step, total_steps)} steps match!`);
        if (options.start_step > 1) {
            console.log(`(Steps 1-${options.start_step - 1} not compared due to MARS CLI limitation)`);
        }
    } else {
        console.log(`\nFAILED: First mismatch at step ${first_mismatch_step}`);
        process.exit(1);
    }
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
