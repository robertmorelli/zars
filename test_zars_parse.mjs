#!/usr/bin/env node
import fs from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const script_dir = path.dirname(fileURLToPath(import.meta.url));
const wasm_path = path.join(script_dir, 'zig-out/bin/lib/zars_runtime.wasm');

const wasm_buffer = fs.readFileSync(wasm_path);
const wasm = await WebAssembly.instantiate(wasm_buffer, {});
const instance = wasm.instance;

const program_text = fs.readFileSync('test_programs/smc.s', 'utf8');
const text_encoder = new TextEncoder();
const encoded_program = text_encoder.encode(program_text);

const memory = new Uint8Array(instance.exports.memory.buffer);
const input_ptr = instance.exports.get_program_input_ptr();

memory.set(encoded_program, input_ptr);

const options = 0 | (1 << 1); // smc enabled
const status = instance.exports.init_execution(encoded_program.length, options);

console.log('Parse status:', status);
console.log('Instruction count:', instance.exports.get_instruction_count());
