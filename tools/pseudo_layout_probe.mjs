#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const script_dir = path.dirname(fileURLToPath(import.meta.url));
const repo_root = path.resolve(script_dir, "..");
const pseudo_ops_path = path.join(repo_root, "MARS/PseudoOps.txt");
const runtime_main_path = path.join(repo_root, "tools/runtime_main.mjs");

function parse_args(argv) {
    const options = {
        out_dir: "/tmp/zars_pseudo_layout_probe",
        refresh_golden: true,
        run_compare: true,
    };

    let index = 0;
    while (index < argv.length) {
        const arg = argv[index];
        if (arg === "--out-dir") {
            index += 1;
            options.out_dir = argv[index] ?? options.out_dir;
        } else if (arg === "--no-refresh") {
            options.refresh_golden = false;
        } else if (arg === "--generate-only") {
            options.run_compare = false;
            options.refresh_golden = false;
        } else if (arg === "--help" || arg === "-h") {
            print_help();
            process.exit(0);
        } else {
            throw new Error(`Unknown argument: ${arg}`);
        }
        index += 1;
    }

    return options;
}

function print_help() {
    const lines = [
        "pseudo_layout_probe.mjs",
        "",
        "Generate and run a large pseudo-op text-layout differential probe.",
        "",
        "Usage:",
        "  node tools/pseudo_layout_probe.mjs [options]",
        "",
        "Options:",
        "  --out-dir <path>      Working directory for generated cases",
        "  --no-refresh          Skip refreshing MARS goldens",
        "  --generate-only       Only generate files; do not run harness",
        "  --help                Show this help",
    ];
    console.log(lines.join("\n"));
}

function normalize_sample(sample) {
    // Generated fixtures need a concrete label symbol instead of placeholder text.
    return sample.replace(/\blabel\b/g, "data_label");
}

function generate_probe_manifest(options) {
    const out_dir = path.resolve(options.out_dir);
    const cases_dir = path.join(out_dir, "cases");
    const expected_dir = path.join(out_dir, "expected");
    const manifest_path = path.join(out_dir, "manifest.json");

    fs.rmSync(out_dir, { recursive: true, force: true });
    fs.mkdirSync(cases_dir, { recursive: true });
    fs.mkdirSync(expected_dir, { recursive: true });

    const lines = fs.readFileSync(pseudo_ops_path, "utf8").split(/\r?\n/);
    const cases = [];

    let case_index = 0;
    for (const raw_line of lines) {
        if (raw_line.length === 0) continue;
        if (raw_line.startsWith("#")) continue;
        if (/^\s/.test(raw_line)) continue;

        const fields = raw_line.split("\t").filter((field) => field.length > 0);
        if (fields.length < 2) continue;

        const sample = normalize_sample(fields[0].trim());
        if (sample.length === 0) continue;
        if (sample.startsWith(".")) continue;

        const case_id = `pseudo_probe_${String(case_index).padStart(3, "0")}`;
        const case_program_path = path.join(cases_dir, `${case_id}.s`);
        const case_expected_path = path.join(expected_dir, `${case_id}.stdout`);

        const source_lines = [
            ".data",
            "data_label: .word 0",
            ".text",
            "main:",
            "    la   $t0, after",
            "    la   $t1, before",
            "    subu $a0, $t0, $t1",
            "    li   $v0, 1",
            "    syscall",
            "    li   $v0, 10",
            "    syscall",
            "before:",
            `    ${sample}`,
            "after:",
            "    nop",
            "",
        ];

        fs.writeFileSync(case_program_path, source_lines.join("\n"), "utf8");

        cases.push({
            id: case_id,
            description: sample,
            program_path: case_program_path,
            mars_options: ["nc"],
            mars_extra_args: [],
            stdin_text: "",
            expected_stdout_path: case_expected_path,
        });

        case_index += 1;
    }

    fs.writeFileSync(manifest_path, JSON.stringify({ version: 1, cases }, null, 2), "utf8");

    return {
        manifest_path,
        case_count: cases.length,
    };
}

function run_runtime_harness(args) {
    const result = spawnSync("node", [runtime_main_path, ...args], {
        cwd: repo_root,
        stdio: "inherit",
        env: {
            ...process.env,
            // Keep zig cache writes inside the repo for sandbox-safe runs.
            ZIG_GLOBAL_CACHE_DIR: path.join(repo_root, ".zig-cache"),
        },
    });

    if (result.error) throw result.error;
    if ((result.status ?? 1) !== 0) process.exit(result.status ?? 1);
}

function main() {
    const options = parse_args(process.argv.slice(2));
    const generated = generate_probe_manifest(options);

    console.log(`Generated ${generated.case_count} pseudo probe cases.`);
    console.log(`Manifest: ${generated.manifest_path}`);

    if (!options.run_compare) return;

    if (options.refresh_golden) {
        run_runtime_harness([
            "--refresh-golden",
            "--engine",
            "mars",
            "--no-state-parity",
            "--manifest",
            generated.manifest_path,
        ]);
    }

    run_runtime_harness([
        "--engine",
        "compare",
        "--no-state-parity",
        "--manifest",
        generated.manifest_path,
    ]);
}

main();
