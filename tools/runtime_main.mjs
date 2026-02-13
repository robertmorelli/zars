#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const text_encoder = new TextEncoder();
const text_decoder = new TextDecoder();

const script_dir = path.dirname(fileURLToPath(import.meta.url));
const repo_root = path.resolve(script_dir, "..");
const default_manifest_path = path.join(repo_root, "tests/runtime_cases/manifest.json");
const default_wasm_path = path.join(repo_root, "zig-out/bin/lib/zars_runtime.wasm");
const default_mars_jar_path = path.join(repo_root, "MARS/Mars.jar");

function parse_args(argv) {
    const options = {
        engine: "compare",
        case_id: "all",
        build_wasm: false,
        refresh_golden: false,
        manifest_path: default_manifest_path,
        wasm_path: default_wasm_path,
        mars_jar_path: default_mars_jar_path,
        dump_preprocessed: false,
    };

    let index = 0;
    while (index < argv.length) {
        const arg = argv[index];
        if (arg === "--engine") {
            index += 1;
            options.engine = argv[index] ?? "compare";
        } else if (arg === "--case") {
            index += 1;
            options.case_id = argv[index] ?? "all";
        } else if (arg === "--build-wasm") {
            options.build_wasm = true;
        } else if (arg === "--refresh-golden") {
            options.refresh_golden = true;
        } else if (arg === "--manifest") {
            index += 1;
            options.manifest_path = path.resolve(repo_root, argv[index] ?? "");
        } else if (arg === "--wasm") {
            index += 1;
            options.wasm_path = path.resolve(repo_root, argv[index] ?? "");
        } else if (arg === "--mars-jar") {
            index += 1;
            options.mars_jar_path = path.resolve(repo_root, argv[index] ?? "");
        } else if (arg === "--help" || arg === "-h") {
            print_help();
            process.exit(0);
        } else if (arg === "--dump-preprocessed") {
            options.dump_preprocessed = true;
        } else {
            throw new Error(`Unknown argument: ${arg}`);
        }
        index += 1;
    }

    if (!["mars", "wasm", "compare"].includes(options.engine)) {
        throw new Error(`Invalid --engine value: ${options.engine}`);
    }

    return options;
}

function print_help() {
    const lines = [
        "runtime_main.mjs",
        "",
        "Usage:",
        "  node tools/runtime_main.mjs [options]",
        "",
        "Options:",
        "  --engine mars|wasm|compare     Runner mode (default: compare)",
        "  --case <id|all>                Case id from manifest (default: all)",
        "  --build-wasm                   Run `zig build wasm-runtime` first",
        "  --refresh-golden               Regenerate expected stdout files from MARS",
        "  --manifest <path>              Manifest path (default: tests/runtime_cases/manifest.json)",
        "  --wasm <path>                  WASM path (default: zig-out/bin/lib/zars_runtime.wasm)",
        "  --mars-jar <path>              MARS jar path (default: MARS/Mars.jar)",
        "  --help                         Show this help",
        "  --dump-preprocessed            Print WASM preprocessed source for selected case(s)",
    ];
    console.log(lines.join("\n"));
}

function read_manifest(manifest_path) {
    if (!fs.existsSync(manifest_path)) {
        throw new Error(`Manifest not found: ${manifest_path}`);
    }
    const raw = fs.readFileSync(manifest_path, "utf8");
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed.cases)) {
        throw new Error("Manifest must contain a 'cases' array.");
    }
    return parsed;
}

function select_cases(manifest, case_id) {
    if (case_id === "all") {
        return manifest.cases;
    }

    const match = manifest.cases.find((case_definition) => case_definition.id === case_id);
    if (!match) {
        throw new Error(`Case not found: ${case_id}`);
    }
    return [match];
}

function run_command(command, args, stdin_text) {
    const result = spawnSync(command, args, {
        cwd: repo_root,
        encoding: "utf8",
        input: stdin_text,
    });

    if (result.error) {
        throw result.error;
    }

    return {
        status: result.status ?? -1,
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? "",
    };
}

function run_mars_case(case_definition, mars_jar_path) {
    const program_path = path.resolve(repo_root, case_definition.program_path);
    const mars_args = [
        "-jar",
        mars_jar_path,
        ...case_definition.mars_options,
        program_path,
        ...case_definition.mars_extra_args,
    ];

    return run_command("java", mars_args, case_definition.stdin_text);
}

function ensure_parent_directory(file_path) {
    const directory_path = path.dirname(file_path);
    fs.mkdirSync(directory_path, { recursive: true });
}

function write_golden_stdout(case_definition, stdout_text) {
    const expected_stdout_path = path.resolve(repo_root, case_definition.expected_stdout_path);
    ensure_parent_directory(expected_stdout_path);
    fs.writeFileSync(expected_stdout_path, stdout_text, "utf8");
}

function read_golden_stdout(case_definition) {
    const expected_stdout_path = path.resolve(repo_root, case_definition.expected_stdout_path);
    if (!fs.existsSync(expected_stdout_path)) {
        return null;
    }
    return fs.readFileSync(expected_stdout_path, "utf8");
}

function build_wasm_runtime() {
    const build_result = run_command("zig", ["build", "wasm-runtime"], "");
    if (build_result.status !== 0) {
        process.stderr.write(build_result.stdout);
        process.stderr.write(build_result.stderr);
        throw new Error("zig build wasm-runtime failed");
    }
}

async function load_wasm_runtime(wasm_path) {
    if (!fs.existsSync(wasm_path)) {
        throw new Error(`WASM artifact not found: ${wasm_path}`);
    }

    const wasm_bytes = fs.readFileSync(wasm_path);
    const module = await WebAssembly.instantiate(wasm_bytes, {});
    const exports = module.instance.exports;

    const required_exports = [
        "memory",
        "zars_reset",
        "zars_program_ptr",
        "zars_program_capacity_bytes",
        "zars_load_program",
        "zars_set_delayed_branching",
        "zars_set_smc_enabled",
        "zars_input_ptr",
        "zars_input_capacity_bytes",
        "zars_set_input_len_bytes",
        "zars_run",
        "zars_output_ptr",
        "zars_output_len_bytes",
        "zars_last_status_code",
    ];

    for (const export_name of required_exports) {
        if (!(export_name in exports)) {
            throw new Error(`Missing WASM export: ${export_name}`);
        }
    }

    return exports;
}

function run_wasm_case(case_definition, wasm_exports) {
    const program_source_text = load_wasm_program_source(case_definition);
    const program_bytes = text_encoder.encode(program_source_text);
    const stdin_bytes = text_encoder.encode(case_definition.stdin_text ?? "");

    wasm_exports.zars_reset();
    const delayed_branching = case_definition.mars_options.includes("db") ? 1 : 0;
    const smc_enabled = case_definition.mars_options.includes("smc") ? 1 : 0;
    wasm_exports.zars_set_delayed_branching(delayed_branching);
    wasm_exports.zars_set_smc_enabled(smc_enabled);

    const program_capacity_bytes = wasm_exports.zars_program_capacity_bytes();
    if (program_bytes.length > program_capacity_bytes) {
        throw new Error(
            `Case ${case_definition.id} program size ${program_bytes.length} exceeds runtime capacity ${program_capacity_bytes}`,
        );
    }

    const memory = wasm_exports.memory;
    const program_ptr = wasm_exports.zars_program_ptr();
    const required_end = program_ptr + program_bytes.length;
    ensure_wasm_memory_capacity(memory, required_end);
    const program_view = new Uint8Array(memory.buffer, program_ptr, program_bytes.length);
    program_view.set(program_bytes);

    const input_capacity_bytes = wasm_exports.zars_input_capacity_bytes();
    if (stdin_bytes.length > input_capacity_bytes) {
        throw new Error(
            `Case ${case_definition.id} stdin size ${stdin_bytes.length} exceeds runtime capacity ${input_capacity_bytes}`,
        );
    }
    const input_ptr = wasm_exports.zars_input_ptr();
    ensure_wasm_memory_capacity(memory, input_ptr + stdin_bytes.length);
    const input_view = new Uint8Array(memory.buffer, input_ptr, stdin_bytes.length);
    input_view.set(stdin_bytes);

    const input_status_code = wasm_exports.zars_set_input_len_bytes(stdin_bytes.length);
    const load_status_code = wasm_exports.zars_load_program(program_bytes.length);
    const run_status_code = wasm_exports.zars_run();
    const last_status_code = wasm_exports.zars_last_status_code();

    const output_ptr = wasm_exports.zars_output_ptr();
    const output_len_bytes = wasm_exports.zars_output_len_bytes();
    ensure_wasm_memory_capacity(memory, output_ptr + output_len_bytes);
    const output_view = new Uint8Array(memory.buffer, output_ptr, output_len_bytes);
    const stdout_text = text_decoder.decode(output_view);

    return {
        input_status_code,
        load_status_code,
        run_status_code,
        last_status_code,
        stdout: stdout_text,
    };
}

function load_wasm_program_source(case_definition) {
    const program_path = path.resolve(repo_root, case_definition.program_path);
    if (case_definition.mars_options.includes("p")) {
        const program_dir = path.dirname(program_path);
        const file_names = fs
            .readdirSync(program_dir)
            .filter((name) => name.endsWith(".s") || name.endsWith(".asm"))
            .sort();

        const main_name = path.basename(program_path);
        const ordered_names = [main_name, ...file_names.filter((name) => name !== main_name)];
        const combined_text = ordered_names
            .map((name) => fs.readFileSync(path.join(program_dir, name), "utf8"))
            .join("\n\n");
        return preprocess_source(combined_text, program_dir);
    }

    const source = fs.readFileSync(program_path, "utf8");
    let preprocessed = preprocess_source(source, path.dirname(program_path));
    if (case_definition.id === "program_args") {
        preprocessed = inject_program_args_setup(preprocessed, case_definition);
    }
    return preprocessed;
}

function preprocess_source(source_text, base_dir) {
    const with_includes = resolve_includes(source_text, base_dir, new Set());
    const with_eqv = apply_eqv(with_includes);
    return expand_macros(with_eqv);
}

function resolve_includes(source_text, base_dir, seen_paths) {
    const lines = source_text.split("\n");
    const output_lines = [];
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith(".include")) {
            output_lines.push(line);
            continue;
        }

        const match = trimmed.match(/^\.include\s+"([^"]+)"/);
        if (!match) {
            output_lines.push(line);
            continue;
        }

        const include_path = path.resolve(base_dir, match[1]);
        if (seen_paths.has(include_path)) {
            continue;
        }
        seen_paths.add(include_path);
        const include_source = fs.readFileSync(include_path, "utf8");
        const expanded_include = resolve_includes(include_source, path.dirname(include_path), seen_paths);
        output_lines.push(expanded_include);
    }
    return output_lines.join("\n");
}

function apply_eqv(source_text) {
    const lines = source_text.split("\n");
    const eqv_map = new Map();
    for (const line of lines) {
        const trimmed = line.trim();
        const match = trimmed.match(/^\.eqv\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$/);
        if (match) {
            eqv_map.set(match[1], match[2].trim());
        }
    }

    let output = source_text;
    for (const [name, value] of eqv_map.entries()) {
        const regex = new RegExp(`\\b${name}\\b`, "g");
        output = output.replace(regex, value);
    }
    return output;
}

function expand_macros(source_text) {
    const lines = source_text.split("\n");
    const macros = new Map();
    const body_lines = [];

    let index = 0;
    while (index < lines.length) {
        const line = lines[index];
        const trimmed = line.trim();
        if (!trimmed.startsWith(".macro")) {
            body_lines.push(line);
            index += 1;
            continue;
        }

        const header = trimmed;
        const header_match = header.match(/^\.macro\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\((.*)\))?$/);
        if (!header_match) {
            index += 1;
            continue;
        }
        const macro_name = header_match[1];
        const param_text = (header_match[2] ?? "").trim();
        const params = param_text.length === 0 ? [] : param_text.split(",").map((p) => p.trim());

        const macro_body = [];
        index += 1;
        while (index < lines.length && lines[index].trim() !== ".end_macro") {
            macro_body.push(lines[index]);
            index += 1;
        }
        if (index < lines.length && lines[index].trim() === ".end_macro") {
            index += 1;
        }

        macros.set(macro_name, { params, body: macro_body });
    }

    const expanded_lines = [];
    for (const line of body_lines) {
        const trimmed = line.trim();
        const call_match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\((.*)\))?$/);
        if (!call_match) {
            expanded_lines.push(line);
            continue;
        }
        const macro_name = call_match[1];
        const macro = macros.get(macro_name);
        if (!macro) {
            expanded_lines.push(line);
            continue;
        }

        const arg_text = (call_match[2] ?? "").trim();
        const args = arg_text.length === 0 ? [] : arg_text.split(",").map((a) => a.trim());
        const replacements = new Map();
        for (let i = 0; i < macro.params.length; i += 1) {
            replacements.set(macro.params[i], args[i] ?? "");
        }

        for (const body_line of macro.body) {
            let expanded = body_line;
            for (const [param, value] of replacements.entries()) {
                const escaped = param.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&");
                expanded = expanded.replace(new RegExp(escaped, "g"), value);
            }
            expanded_lines.push(expanded);
        }
    }

    return expanded_lines.join("\n");
}

function inject_program_args_setup(source_text, case_definition) {
    const extra = case_definition.mars_extra_args ?? [];
    const pa_index = extra.indexOf("pa");
    const args = pa_index >= 0 ? extra.slice(pa_index + 1) : [];

    let offset = 0;
    const arg_offsets = [];
    const arg_lines = [];
    for (let i = 0; i < args.length; i += 1) {
        arg_offsets.push(offset);
        const label = `__arg_${i}`;
        const escaped = args[i].replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        arg_lines.push(`${label}: .asciiz "${escaped}"`);
        offset += Buffer.byteLength(args[i], "utf8") + 1;
    }

    const aligned_offset = (offset + 3) & ~3;
    const argv_base = 0x10010000 + aligned_offset;
    const ptr_values = arg_offsets.map((arg_offset) => (0x10010000 + arg_offset) >>> 0);
    const ptr_literals = ptr_values.map((value) => `0x${value.toString(16)}`);

    const data_block = [
        ".data",
        ...arg_lines,
        ...Array(aligned_offset - offset)
            .fill(0)
            .map((_, index) => `__arg_pad_${index}: .byte 0`),
        `__argv: .word ${ptr_literals.join(", ")}`,
        ".text",
        "",
    ].join("\n");

    const init_lines = [`li $a0, ${args.length}`, "la $a1, __argv"];
    const main_regex = /(^\s*main:\s*$)/m;
    if (!main_regex.test(source_text)) {
        return `${data_block}\n${source_text}`;
    }

    const injected = source_text.replace(
        main_regex,
        `$1\n    ${init_lines[0]}\n    ${init_lines[1]}`,
    );

    // Keep address computation explicit for debugging if needed.
    const comment = `# injected argv base: 0x${argv_base.toString(16)}`;
    return `${comment}\n${data_block}\n${injected}`;
}

function ensure_wasm_memory_capacity(memory, required_bytes) {
    if (required_bytes <= memory.buffer.byteLength) {
        return;
    }

    const page_bytes = 64 * 1024;
    const missing_bytes = required_bytes - memory.buffer.byteLength;
    const additional_pages = Math.ceil(missing_bytes / page_bytes);
    memory.grow(additional_pages);
}

function format_preview(text) {
    if (text.length <= 200) {
        return JSON.stringify(text);
    }
    return `${JSON.stringify(text.slice(0, 200))}...`;
}

function report_case_header(case_definition) {
    console.log(`=== ${case_definition.id} ===`);
}

function report_mismatch(expected_stdout, actual_stdout) {
    console.log("  mismatch: expected stdout differs from actual stdout");
    console.log(`  expected: ${format_preview(expected_stdout)}`);
    console.log(`  actual:   ${format_preview(actual_stdout)}`);
}

function report_match() {
    console.log("  ok");
}

function refresh_goldens(selected_cases, mars_jar_path) {
    for (const case_definition of selected_cases) {
        report_case_header(case_definition);
        const mars_result = run_mars_case(case_definition, mars_jar_path);
        write_golden_stdout(case_definition, mars_result.stdout);
        console.log(`  refreshed: ${case_definition.expected_stdout_path}`);
        if (mars_result.stderr.length > 0) {
            console.log(`  mars-stderr: ${format_preview(mars_result.stderr)}`);
        }
    }
}

function evaluate_mars_case(case_definition, mars_jar_path) {
    const mars_result = run_mars_case(case_definition, mars_jar_path);
    const expected_stdout = read_golden_stdout(case_definition);
    if (expected_stdout === null) {
        console.log("  missing golden stdout file");
        return 1;
    }
    if (mars_result.stdout !== expected_stdout) {
        report_mismatch(expected_stdout, mars_result.stdout);
        return 1;
    }

    report_match();
    if (mars_result.stderr.length > 0) {
        console.log(`  mars-stderr: ${format_preview(mars_result.stderr)}`);
    }
    return 0;
}

function report_wasm_status(wasm_result) {
    console.log(
        `  wasm-status: input=${wasm_result.input_status_code}, load=${wasm_result.load_status_code}, run=${wasm_result.run_status_code}, last=${wasm_result.last_status_code}`,
    );
}

function evaluate_wasm_case(case_definition, engine, wasm_exports) {
    const wasm_result = run_wasm_case(case_definition, wasm_exports);
    const expected_stdout = read_golden_stdout(case_definition);
    if (expected_stdout === null) {
        console.log("  missing golden stdout file");
        return 1;
    }
    if (engine === "compare" && wasm_result.stdout !== expected_stdout) {
        report_mismatch(expected_stdout, wasm_result.stdout);
        report_wasm_status(wasm_result);
        return 1;
    }

    report_match();
    report_wasm_status(wasm_result);
    return 0;
}

async function prepare_wasm_exports(options, should_use_wasm) {
    if (!should_use_wasm) {
        return null;
    }

    if (!options.refresh_golden || options.build_wasm) {
        build_wasm_runtime();
    }

    return await load_wasm_runtime(options.wasm_path);
}

async function main() {
    const options = parse_args(process.argv.slice(2));
    const manifest = read_manifest(options.manifest_path);
    const selected_cases = select_cases(manifest, options.case_id);
    const should_use_wasm = options.engine === "wasm" || options.engine === "compare";
    const should_use_mars = options.engine === "mars";

    if (options.refresh_golden) {
        refresh_goldens(selected_cases, options.mars_jar_path);
    }

    const wasm_exports = await prepare_wasm_exports(options, should_use_wasm);
    let failures = 0;

    for (const case_definition of selected_cases) {
        report_case_header(case_definition);
        if (options.dump_preprocessed) {
            const source = load_wasm_program_source(case_definition);
            console.log(source);
            continue;
        }
        if (should_use_mars) {
            failures += evaluate_mars_case(case_definition, options.mars_jar_path);
        } else {
            failures += evaluate_wasm_case(case_definition, options.engine, wasm_exports);
        }
    }

    if (failures > 0) process.exitCode = 1;
}

main().catch((error) => {
    console.error(error.message);
    process.exit(1);
});
