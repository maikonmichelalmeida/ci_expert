#!/usr/bin/env node

// Gerador especifico do programa didatico rv32i_system_program.
// Nao e um assembler generico: a lista abaixo ja usa somente instrucoes reais
// suportadas pelo core. Os encoders apenas resolvem labels e produzem o HEX.

"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SW_DIR = path.join(ROOT, "sw");
const MEM_DIR = path.join(ROOT, "mem");
const TB_DIR = path.join(ROOT, "tb");

const R = Object.freeze({
    zero: 0, ra: 1, sp: 2, gp: 3, tp: 4,
    t0: 5, t1: 6, t2: 7, s0: 8, fp: 8, s1: 9,
    a0: 10, a1: 11, a2: 12, a3: 13, a4: 14, a5: 15,
    a6: 16, a7: 17, s2: 18, s3: 19, s4: 20, s5: 21,
    s6: 22, s7: 23, s8: 24, s9: 25, s10: 26, s11: 27,
    t3: 28, t4: 29, t5: 30, t6: 31
});

const ABI = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
];

const PASS_STATUS = 0x600d600d >>> 0;
const FAIL_STATUS = 0xbad0bad0 >>> 0;
const BRANCH_SIGNATURE = 0x3f;
const MEMORY_SIGNATURE = 0x135;

function s32(x) { return x | 0; }
function u32(x) { return x >>> 0; }
function checkSigned(value, bits, what) {
    const min = -(2 ** (bits - 1));
    const max = (2 ** (bits - 1)) - 1;
    if (!Number.isInteger(value) || value < min || value > max)
        throw new Error(`${what}=${value} fora do range signed de ${bits} bits`);
}
function checkUnsigned(value, bits, what) {
    const max = (2 ** bits) - 1;
    if (!Number.isInteger(value) || value < 0 || value > max)
        throw new Error(`${what}=${value} fora do range unsigned de ${bits} bits`);
}
function bits(value, width) { return value & ((2 ** width) - 1); }
function hex32(value) { return u32(value).toString(16).padStart(8, "0"); }
function hexPc(value) { return u32(value).toString(16).padStart(8, "0"); }

function computeAluSignature() {
    let acc = 0 >>> 0;
    const mix = value => { acc = u32(acc ^ u32(value)); };
    const neg16 = 0xfffffff0 >>> 0;
    const three = 3;
    let v = 5; mix(v);                 // ADDI
    v = u32(v << 2); mix(v);           // SLLI
    mix(1);                            // SLTI
    mix(0);                            // SLTIU
    v = u32(v ^ 0x55); mix(v);         // XORI
    mix(neg16 >>> 2);                  // SRLI
    mix(u32(s32(neg16) >> 2));         // SRAI
    v = u32(v | 0x100); mix(v);        // ORI
    v = u32(v & 0xff); mix(v);         // ANDI
    mix(u32(neg16 + three));           // ADD
    mix(u32(three - neg16));           // SUB
    mix(u32(three << three));          // SLL
    mix(1);                            // SLT
    mix(0);                            // SLTU
    mix(u32(neg16 ^ three));           // XOR
    mix(neg16 >>> three);              // SRL
    mix(u32(s32(neg16) >> three));     // SRA
    mix(u32(neg16 | three));           // OR
    mix(u32(neg16 & three));           // AND
    mix(123);                          // WB -> Decode marker
    mix(2);                            // dependent ADDI marker
    return acc >>> 0;
}

const ALU_SIGNATURE = computeAluSignature();
const program = [];
const asmItems = [];
const labels = new Map();

function comment(text = "") { asmItems.push({ kind: "comment", text }); }
function banner(lines) {
    comment("# ------------------------------------------------------------");
    for (const line of lines) comment(`# ${line}`);
    comment("# ------------------------------------------------------------");
}
function label(name) {
    if (labels.has(name)) throw new Error(`label duplicado: ${name}`);
    labels.set(name, program.length);
    asmItems.push({ kind: "label", name });
}
function emit(op, args, note = "") {
    const insn = { op, args, note, index: program.length };
    program.push(insn);
    asmItems.push({ kind: "instruction", insn });
}
function i(op, rd, rs1, imm, note = "") { emit(op, { rd, rs1, imm }, note); }
function r(op, rd, rs1, rs2, note = "") { emit(op, { rd, rs1, rs2 }, note); }
function load(op, rd, imm, rs1, note = "") { emit(op, { rd, imm, rs1 }, note); }
function store(op, rs2, imm, rs1, note = "") { emit(op, { rs2, imm, rs1 }, note); }
function branch(op, rs1, rs2, target, note = "") {
    emit(op, { rs1, rs2, target }, note);
}
function upper(op, rd, imm20, note = "") { emit(op, { rd, imm20 }, note); }
function jal(rd, target, note = "") { emit("jal", { rd, target }, note); }
function jalr(rd, imm, rs1, note = "") { emit("jalr", { rd, imm, rs1 }, note); }
function call(target, note = "") { jal(R.ra, target, note || `call ${target}`); }
function jump(target, note = "") { jal(R.zero, target, note || `jump ${target}`); }
function ret(note = "return") { jalr(R.zero, 0, R.ra, note); }
function addiLabel(rd, rs1, target, note = "") {
    emit("addi_label", { rd, rs1, target }, note);
}
function li32(rd, value, note = "") {
    const valueU = u32(value);
    const low = ((valueU & 0xfff) << 20) >> 20;
    const high = ((valueU - low) >>> 12) & 0xfffff;
    if (high !== 0) {
        upper("lui", rd, high, note);
        if (low !== 0) i("addi", rd, rd, low, "parte baixa");
    } else {
        i("addi", rd, R.zero, low, note);
    }
}

comment(".section .text");
comment(".globl _start");
comment("");

banner([
    "_start: inicializacao bare-metal e publicacao atomica do status.",
    "sp comeca em 0x800; chama main; valida retorno e restauracao da stack.",
    "PASS/FAIL e a ultima escrita significativa antes do loop final."
]);
label("_start");
upper("lui", R.sp, 0x1, "sp recebe 0x1000");
i("addi", R.sp, R.sp, -2048, "sp = 0x800");
store("sw", R.zero, 0x1f0, R.zero, "status inicial = 0");
store("sw", R.zero, 0x1f4, R.zero, "error inicial = 0");
call("main");
i("addi", R.t0, R.a0, 0, "preserva codigo retornado por main");
store("sw", R.sp, 0x1f8, R.zero, "snapshot final do sp");
branch("bne", R.t0, R.zero, "start_fail_code");
upper("lui", R.t1, 0x1);
i("addi", R.t1, R.t1, -2048, "valor esperado de sp");
branch("bne", R.sp, R.t1, "start_fail_stack");
store("sw", R.zero, 0x1f4, R.zero, "error=0 antes do status");
li32(R.t2, PASS_STATUS, "assinatura PASS");
store("sw", R.t2, 0x1f0, R.zero, "commit final de sucesso");
jump("done");
label("start_fail_stack");
i("addi", R.t0, R.zero, 13, "erro 13: stack");
label("start_fail_code");
store("sw", R.t0, 0x1f4, R.zero, "publica o codigo antes do FAIL");
li32(R.t2, FAIL_STATUS, "assinatura FAIL");
store("sw", R.t2, 0x1f0, R.zero, "commit final de falha");
label("done");
jump("done", "loop final observavel no waveform");

banner([
    "int main(void)",
    "non-leaf; frame 16 bytes; salva ra em 12(sp).",
    "chama run_suite e verify_results; retorna codigo em a0.",
    "O epilogo cria deliberadamente LW ra -> JALR imediato."
]);
label("main");
i("addi", R.sp, R.sp, -16);
store("sw", R.ra, 12, R.sp);
call("run_suite");
branch("bne", R.a0, R.zero, "main_return");
call("verify_results");
label("main_return");
i("addi", R.sp, R.sp, 16, "restaura sp antes de buscar ra");
load("lw", R.ra, -4, R.sp, "ra salvo no antigo 12(sp)");
ret("retorno imediato apos LOAD: exercita load-use JALR");

banner([
    "int run_suite(void)",
    "non-leaf; frame 16 bytes; salva ra.",
    "Inicializa vetores, chama todas as rotinas e grava resultados."
]);
label("run_suite");
i("addi", R.sp, R.sp, -16);
store("sw", R.ra, 12, R.sp);

comment("# A=[7,-3,12,4] e B=[2,5,-1,6], produzidos por software.");
i("addi", R.t0, R.zero, 7);   store("sw", R.t0, 0x100, R.zero);
i("addi", R.t0, R.zero, -3);  store("sw", R.t0, 0x104, R.zero);
i("addi", R.t0, R.zero, 12);  store("sw", R.t0, 0x108, R.zero);
i("addi", R.t0, R.zero, 4);   store("sw", R.t0, 0x10c, R.zero);
i("addi", R.t0, R.zero, 2);   store("sw", R.t0, 0x120, R.zero);
i("addi", R.t0, R.zero, 5);   store("sw", R.t0, 0x124, R.zero);
i("addi", R.t0, R.zero, -1);  store("sw", R.t0, 0x128, R.zero);
i("addi", R.t0, R.zero, 6);   store("sw", R.t0, 0x12c, R.zero);

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 4);
call("sum_array");
store("sw", R.a0, 0x180, R.zero);
label("load_store_copy_load");
load("lw", R.t0, 0x180, R.zero, "resultado da soma");
store("sw", R.t0, 0x1ac, R.zero,
      "LOAD -> STORE.rs2 consecutivo: bypass tardio WB->MEM");

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 4);
call("minmax");
store("sw", R.a0, 0x184, R.zero); store("sw", R.a1, 0x188, R.zero);

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 0x120);
i("addi", R.a2, R.zero, 4); call("dot_product");
store("sw", R.a0, 0x194, R.zero);

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 4);
call("insertion_sort");

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 0);
i("addi", R.a2, R.zero, 3); i("addi", R.a3, R.zero, 12);
call("binary_search_recursive"); store("sw", R.a0, 0x18c, R.zero);

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 0);
i("addi", R.a2, R.zero, 3); i("addi", R.a3, R.zero, 5);
call("binary_search_recursive"); store("sw", R.a0, 0x190, R.zero);

i("addi", R.a0, R.zero, 0x100); i("addi", R.a1, R.zero, 16);
call("checksum8"); store("sw", R.a0, 0x198, R.zero);

i("addi", R.a0, R.zero, 0x1b0); call("memory_probe");
store("sw", R.a0, 0x1a4, R.zero);
call("branch_probe"); store("sw", R.a0, 0x19c, R.zero);
call("alu_probe"); store("sw", R.a0, 0x1a0, R.zero);
call("pc_probe"); store("sw", R.a0, 0x1a8, R.zero);

i("addi", R.a0, R.zero, 0, "run_suite terminou");
i("addi", R.sp, R.sp, 16);
load("lw", R.ra, -4, R.sp);
ret();

banner([
    "int sum_array(int *v, int n)",
    "leaf; sem frame; a0=v, a1=n; retorna soma em a0.",
    "LW seguido imediatamente por ADD cria load-use real."
]);
label("sum_array");
i("addi", R.t0, R.zero, 0, "sum=0");
label("sum_array_loop");
branch("beq", R.a1, R.zero, "sum_array_done");
load("lw", R.t1, 0, R.a0);
r("add", R.t0, R.t0, R.t1, "sum += *v (consumidor imediato)");
i("addi", R.a0, R.a0, 4);
i("addi", R.a1, R.a1, -1);
jump("sum_array_loop");
label("sum_array_done");
i("addi", R.a0, R.t0, 0);
ret();

banner([
    "void minmax(int *v, int n), retorno a0=min e a1=max",
    "leaf; sem frame; BLT/BGE fazem comparacoes signed."
]);
label("minmax");
load("lw", R.t0, 0, R.a0);
i("addi", R.t1, R.t0, 0, "min=v[0]");
i("addi", R.t2, R.t0, 0, "max=v[0]");
i("addi", R.a0, R.a0, 4);
i("addi", R.a1, R.a1, -1);
label("minmax_loop");
branch("beq", R.a1, R.zero, "minmax_done");
load("lw", R.t3, 0, R.a0);
branch("blt", R.t3, R.t1, "minmax_set_min");
branch("bge", R.t3, R.t2, "minmax_set_max");
jump("minmax_next");
label("minmax_set_min");
i("addi", R.t1, R.t3, 0);
jump("minmax_next");
label("minmax_set_max");
i("addi", R.t2, R.t3, 0);
label("minmax_next");
i("addi", R.a0, R.a0, 4);
i("addi", R.a1, R.a1, -1);
jump("minmax_loop");
label("minmax_done");
i("addi", R.a0, R.t1, 0);
i("addi", R.a1, R.t2, 0);
ret();

banner([
    "int dot_product(int *a, int *b, int n)",
    "non-leaf; frame 32 bytes; salva ra,s0,s1,s2,s3.",
    "chama mul_signed a cada elemento e preserva ponteiros/contador."
]);
label("dot_product");
i("addi", R.sp, R.sp, -32);
store("sw", R.ra, 28, R.sp); store("sw", R.s0, 24, R.sp);
store("sw", R.s1, 20, R.sp); store("sw", R.s2, 16, R.sp);
store("sw", R.s3, 12, R.sp);
i("addi", R.s0, R.a0, 0); i("addi", R.s1, R.a1, 0);
i("addi", R.s2, R.a2, 0); i("addi", R.s3, R.zero, 0);
label("dot_product_loop");
branch("beq", R.s2, R.zero, "dot_product_done");
load("lw", R.a0, 0, R.s0); load("lw", R.a1, 0, R.s1);
call("mul_signed");
r("add", R.s3, R.s3, R.a0);
i("addi", R.s0, R.s0, 4); i("addi", R.s1, R.s1, 4);
i("addi", R.s2, R.s2, -1); jump("dot_product_loop");
label("dot_product_done");
i("addi", R.a0, R.s3, 0);
load("lw", R.s3, 12, R.sp); load("lw", R.s2, 16, R.sp);
load("lw", R.s1, 20, R.sp); load("lw", R.s0, 24, R.sp);
load("lw", R.ra, 28, R.sp); i("addi", R.sp, R.sp, 32); ret();

banner([
    "int mul_signed(int a, int b)",
    "non-leaf; frame 32 bytes; salva ra,s0,s1,s2,s3.",
    "chama abs32 duas vezes e multiplica por somas sucessivas."
]);
label("mul_signed");
i("addi", R.sp, R.sp, -32);
store("sw", R.ra, 28, R.sp); store("sw", R.s0, 24, R.sp);
store("sw", R.s1, 20, R.sp); store("sw", R.s2, 16, R.sp);
store("sw", R.s3, 12, R.sp);
i("addi", R.s0, R.a0, 0); i("addi", R.s1, R.a1, 0);
r("xor", R.s2, R.s0, R.s1, "bit de sinal do produto");
call("abs32"); i("addi", R.s3, R.a0, 0, "abs(a)");
i("addi", R.a0, R.s1, 0); call("abs32");
i("addi", R.t0, R.a0, 0, "contador=abs(b)");
i("addi", R.t1, R.zero, 0, "produto=0");
label("mul_signed_loop");
branch("beq", R.t0, R.zero, "mul_signed_apply_sign");
r("add", R.t1, R.t1, R.s3);
i("addi", R.t0, R.t0, -1);
jump("mul_signed_loop");
label("mul_signed_apply_sign");
branch("bge", R.s2, R.zero, "mul_signed_positive");
r("sub", R.a0, R.zero, R.t1, "reaplica sinal negativo");
jump("mul_signed_epilogue");
label("mul_signed_positive");
i("addi", R.a0, R.t1, 0);
label("mul_signed_epilogue");
load("lw", R.s3, 12, R.sp); load("lw", R.s2, 16, R.sp);
load("lw", R.s1, 20, R.sp); load("lw", R.s0, 24, R.sp);
load("lw", R.ra, 28, R.sp); i("addi", R.sp, R.sp, 32); ret();

banner([
    "int abs32(int x)",
    "leaf; sem frame; nao trata INT32_MIN por decisao desta experiencia."
]);
label("abs32");
branch("bge", R.a0, R.zero, "abs32_done");
r("sub", R.a0, R.zero, R.a0);
label("abs32_done");
ret();

banner([
    "void insertion_sort(int *v, int n)",
    "leaf; sem frame; ordena signed in-place e usa SLLI para index*4."
]);
label("insertion_sort");
i("addi", R.t0, R.zero, 1, "i=1");
label("sort_outer");
branch("bge", R.t0, R.a1, "sort_done");
i("slli", R.t1, R.t0, 2); r("add", R.t1, R.a0, R.t1);
load("lw", R.t2, 0, R.t1, "key=v[i]");
i("addi", R.t3, R.t0, -1, "j=i-1");
label("sort_inner");
branch("blt", R.t3, R.zero, "sort_insert");
i("slli", R.t4, R.t3, 2); r("add", R.t5, R.a0, R.t4);
load("lw", R.t6, 0, R.t5);
branch("bge", R.t2, R.t6, "sort_insert");
store("sw", R.t6, 4, R.t5, "v[j+1]=v[j]");
i("addi", R.t3, R.t3, -1); jump("sort_inner");
label("sort_insert");
i("addi", R.t4, R.t3, 1); i("slli", R.t4, R.t4, 2);
r("add", R.t5, R.a0, R.t4); store("sw", R.t2, 0, R.t5);
i("addi", R.t0, R.t0, 1); jump("sort_outer");
label("sort_done");
ret();

banner([
    "int binary_search_recursive(int *v,int lo,int hi,int target)",
    "recursive/non-leaf; frame 32 bytes; salva ra,s0,s1,s2,s3.",
    "Cada caminho recursivo usa JAL real; retorno usa JALR."
]);
label("binary_search_recursive");
i("addi", R.sp, R.sp, -32);
store("sw", R.ra, 28, R.sp); store("sw", R.s0, 24, R.sp);
store("sw", R.s1, 20, R.sp); store("sw", R.s2, 16, R.sp);
store("sw", R.s3, 12, R.sp);
i("addi", R.s0, R.a0, 0); i("addi", R.s1, R.a1, 0);
i("addi", R.s2, R.a2, 0); i("addi", R.s3, R.a3, 0);
branch("blt", R.s2, R.s1, "binary_not_found", "hi < lo");
r("add", R.t0, R.s1, R.s2); i("srli", R.t0, R.t0, 1, "mid=(lo+hi)>>1");
i("slli", R.t1, R.t0, 2); r("add", R.t1, R.s0, R.t1);
load("lw", R.t2, 0, R.t1);
branch("beq", R.t2, R.s3, "binary_found", "load-use no branch");
branch("blt", R.t2, R.s3, "binary_right");
comment("# Busca esquerda: [lo,mid-1].");
i("addi", R.a0, R.s0, 0); i("addi", R.a1, R.s1, 0);
i("addi", R.a2, R.t0, -1); i("addi", R.a3, R.s3, 0);
call("binary_search_recursive", "chamada recursiva esquerda");
jump("binary_epilogue");
label("binary_right");
i("addi", R.a0, R.s0, 0); i("addi", R.a1, R.t0, 1);
i("addi", R.a2, R.s2, 0); i("addi", R.a3, R.s3, 0);
call("binary_search_recursive", "chamada recursiva direita");
jump("binary_epilogue");
label("binary_found");
i("addi", R.a0, R.t0, 0);
jump("binary_epilogue");
label("binary_not_found");
i("addi", R.a0, R.zero, -1);
label("binary_epilogue");
load("lw", R.s3, 12, R.sp); load("lw", R.s2, 16, R.sp);
load("lw", R.s1, 20, R.sp); load("lw", R.s0, 24, R.sp);
load("lw", R.ra, 28, R.sp); i("addi", R.sp, R.sp, 32); ret();

banner([
    "uint32_t checksum8(const int32_t *v, int bytes)",
    "leaf; percorre os 16 bytes little-endian com LBU e XOR."
]);
label("checksum8");
i("addi", R.t0, R.zero, 0);
label("checksum8_loop");
branch("beq", R.a1, R.zero, "checksum8_done");
load("lbu", R.t1, 0, R.a0);
r("xor", R.t0, R.t0, R.t1);
i("addi", R.a0, R.a0, 1); i("addi", R.a1, R.a1, -1);
jump("checksum8_loop");
label("checksum8_done");
i("addi", R.a0, R.t0, 0); ret();

banner([
    "int memory_probe(uint8_t *scratch)",
    "leaf; monta palavras por SB/SH e valida LB/LBU/LH/LHU/LW.",
    "Retorna 0x135 em sucesso ou zero em falha."
]);
label("memory_probe");
i("addi", R.t0, R.zero, 1);    store("sb", R.t0, 0, R.a0);
i("addi", R.t0, R.zero, 127);  store("sb", R.t0, 1, R.a0);
i("addi", R.t0, R.zero, -1);   store("sb", R.t0, 2, R.a0);
i("addi", R.t0, R.zero, -128); store("sb", R.t0, 3, R.a0);
load("lw", R.t1, 0, R.a0); li32(R.t2, 0x80ff7f01);
branch("bne", R.t1, R.t2, "memory_probe_fail");
load("lb", R.t1, 3, R.a0); i("addi", R.t2, R.zero, -128);
branch("bne", R.t1, R.t2, "memory_probe_fail");
load("lbu", R.t1, 3, R.a0); i("addi", R.t2, R.zero, 128);
branch("bne", R.t1, R.t2, "memory_probe_fail");
li32(R.t0, 0x00007fff); store("sh", R.t0, 4, R.a0);
li32(R.t0, 0x00008001); store("sh", R.t0, 6, R.a0);
load("lh", R.t1, 6, R.a0); li32(R.t2, 0xffff8001);
branch("bne", R.t1, R.t2, "memory_probe_fail");
load("lhu", R.t1, 6, R.a0); li32(R.t2, 0x00008001);
branch("bne", R.t1, R.t2, "memory_probe_fail");
load("lw", R.t1, 4, R.a0); li32(R.t2, 0x80017fff);
branch("bne", R.t1, R.t2, "memory_probe_fail");
i("addi", R.a0, R.zero, MEMORY_SIGNATURE); ret();
label("memory_probe_fail");
i("addi", R.a0, R.zero, 0); ret();

banner([
    "uint32_t branch_probe(void)",
    "leaf; exercita BEQ/BNE/BLT/BGE/BLTU/BGEU.",
    "-3 < 7 signed, mas 0xfffffffd >= 7 unsigned; assinatura=0x3f."
]);
label("branch_probe");
i("addi", R.t0, R.zero, 0); i("addi", R.t1, R.zero, -3);
i("addi", R.t2, R.zero, 7);
branch("beq", R.t1, R.t2, "branch_probe_fail", "BEQ nao tomado");
branch("beq", R.t1, R.t1, "branch_beq_ok", "BEQ tomado");
jump("branch_probe_fail");
label("branch_beq_ok"); i("ori", R.t0, R.t0, 1);
branch("bne", R.t1, R.t1, "branch_probe_fail", "BNE nao tomado");
branch("bne", R.t1, R.t2, "branch_bne_ok", "BNE tomado");
jump("branch_probe_fail");
label("branch_bne_ok"); i("ori", R.t0, R.t0, 2);
branch("blt", R.t1, R.t2, "branch_blt_ok"); jump("branch_probe_fail");
label("branch_blt_ok"); i("ori", R.t0, R.t0, 4);
branch("bge", R.t2, R.t1, "branch_bge_ok"); jump("branch_probe_fail");
label("branch_bge_ok"); i("ori", R.t0, R.t0, 8);
branch("bltu", R.t2, R.t1, "branch_bltu_ok"); jump("branch_probe_fail");
label("branch_bltu_ok"); i("ori", R.t0, R.t0, 16);
branch("bgeu", R.t1, R.t2, "branch_bgeu_ok"); jump("branch_probe_fail");
label("branch_bgeu_ok"); i("ori", R.a0, R.t0, 32); ret();
label("branch_probe_fail"); i("addi", R.a0, R.zero, 0); ret();

banner([
    "uint32_t alu_probe(void)",
    "leaf; cada resultado participa da assinatura ou de um check.",
    "Cobre as nove OP-IMM e as dez OP, incluindo signed/unsigned e SRL/SRA."
]);
label("alu_probe");
i("addi", R.t0, R.zero, 0, "assinatura");
i("addi", R.t1, R.zero, -16); i("addi", R.t2, R.zero, 3);
i("addi", R.t3, R.zero, 5); r("xor", R.t0, R.t0, R.t3);
i("slli", R.t3, R.t3, 2); r("xor", R.t0, R.t0, R.t3);
i("slti", R.t4, R.t1, 0); r("xor", R.t0, R.t0, R.t4);
i("sltiu", R.t4, R.t1, 1); branch("bne", R.t4, R.zero, "alu_probe_fail");
r("xor", R.t0, R.t0, R.t4);
i("xori", R.t3, R.t3, 0x55); r("xor", R.t0, R.t0, R.t3);
i("srli", R.t4, R.t1, 2); r("xor", R.t0, R.t0, R.t4);
i("srai", R.t5, R.t1, 2); r("xor", R.t0, R.t0, R.t5);
i("ori", R.t3, R.t3, 0x100); r("xor", R.t0, R.t0, R.t3);
i("andi", R.t3, R.t3, 0xff); r("xor", R.t0, R.t0, R.t3);
r("add", R.t3, R.t1, R.t2); r("xor", R.t0, R.t0, R.t3);
r("sub", R.t3, R.t2, R.t1); r("xor", R.t0, R.t0, R.t3);
r("sll", R.t3, R.t2, R.t2); r("xor", R.t0, R.t0, R.t3);
r("slt", R.t3, R.t1, R.t2); r("xor", R.t0, R.t0, R.t3);
r("sltu", R.t3, R.t1, R.t2); branch("bne", R.t3, R.zero, "alu_probe_fail");
r("xor", R.t0, R.t0, R.t3);
r("xor", R.t3, R.t1, R.t2); r("xor", R.t0, R.t0, R.t3);
r("srl", R.t3, R.t1, R.t2); r("xor", R.t0, R.t0, R.t3);
r("sra", R.t3, R.t1, R.t2); r("xor", R.t0, R.t0, R.t3);
r("or", R.t3, R.t1, R.t2); r("xor", R.t0, R.t0, R.t3);
r("and", R.t3, R.t1, R.t2); branch("bne", R.t3, R.zero, "alu_probe_fail");
r("xor", R.t0, R.t0, R.t3);
comment("# Distancia de tres instrucoes: t4 chega a WB quando o XOR o le em Decode.");
i("addi", R.t4, R.zero, 123);
i("addi", R.t5, R.zero, 1);
i("addi", R.t5, R.t5, 1);
r("xor", R.t0, R.t0, R.t4, "WB -> Decode funcional");
r("xor", R.t0, R.t0, R.t5);
i("addi", R.a0, R.t0, 0); ret();
label("alu_probe_fail"); i("addi", R.a0, R.zero, 0); ret();

banner([
    "uint32_t pc_probe(void)",
    "leaf; AUIPC com imediato zero retorna o PC da propria instrucao."
]);
label("pc_probe");
label("pc_probe_auipc");
upper("auipc", R.a0, 0, "a0 = PC desta instrucao");
ret();

banner([
    "int verify_results(void)",
    "leaf; sem frame; confere resultados produzidos pelo proprio software.",
    "Retorna 0 ou codigo de erro especifico em a0."
]);
label("verify_results");
function checkMem(addr, expected, errorLabel, note) {
    load("lw", R.t0, addr, R.zero, note);
    li32(R.t1, expected);
    branch("bne", R.t0, R.t1, errorLabel);
}
checkMem(0x180, 20, "verify_error_1", "sum");
checkMem(0x184, -3, "verify_error_2", "min");
checkMem(0x188, 12, "verify_error_3", "max");
checkMem(0x100, -3, "verify_error_4", "A[0]");
checkMem(0x104, 4, "verify_error_4", "A[1]");
checkMem(0x108, 7, "verify_error_4", "A[2]");
checkMem(0x10c, 12, "verify_error_4", "A[3]");
checkMem(0x18c, 3, "verify_error_5", "busca encontrada");
checkMem(0x190, -1, "verify_error_6", "busca ausente");
checkMem(0x194, 11, "verify_error_7", "dot product");
checkMem(0x198, 13, "verify_error_8", "checksum");
checkMem(0x19c, BRANCH_SIGNATURE, "verify_error_9", "branch signature");
checkMem(0x1a0, ALU_SIGNATURE, "verify_error_10", "ALU signature");
checkMem(0x1a4, MEMORY_SIGNATURE, "verify_error_11", "memory signature");
load("lw", R.t0, 0x1a8, R.zero, "pc_probe");
addiLabel(R.t1, R.zero, "pc_probe_auipc", "PC esperado pelo mapa");
branch("bne", R.t0, R.t1, "verify_error_12");
checkMem(0x120, 2, "verify_error_14", "B[0]");
checkMem(0x124, 5, "verify_error_14", "B[1]");
checkMem(0x128, -1, "verify_error_14", "B[2]");
checkMem(0x12c, 6, "verify_error_14", "B[3]");
checkMem(0x1ac, 20, "verify_error_15", "copia LOAD->STORE");
i("addi", R.a0, R.zero, 0); ret();
for (const code of [1,2,3,4,5,6,7,8,9,10,11,12,14,15]) {
    label(`verify_error_${code}`);
    i("addi", R.a0, R.zero, code);
    ret();
}

function targetPc(name) {
    if (!labels.has(name)) throw new Error(`label inexistente: ${name}`);
    return labels.get(name) * 4;
}

const R_TABLE = Object.freeze({
    add: [0x00, 0], sub: [0x20, 0], sll: [0x00, 1], slt: [0x00, 2],
    sltu: [0x00, 3], xor: [0x00, 4], srl: [0x00, 5],
    sra: [0x20, 5], or: [0x00, 6], and: [0x00, 7]
});
const I_TABLE = Object.freeze({
    addi: 0, slti: 2, sltiu: 3, xori: 4, ori: 6, andi: 7
});
const SHIFT_I_TABLE = Object.freeze({ slli: [0x00, 1], srli: [0x00, 5], srai: [0x20, 5] });
const LOAD_TABLE = Object.freeze({ lb: 0, lh: 1, lw: 2, lbu: 4, lhu: 5 });
const STORE_TABLE = Object.freeze({ sb: 0, sh: 1, sw: 2 });
const BRANCH_TABLE = Object.freeze({ beq: 0, bne: 1, blt: 4, bge: 5, bltu: 6, bgeu: 7 });

function encode(insn) {
    let { op, args: a, index } = insn;
    const pc = index * 4;
    if (op === "addi_label") {
        op = "addi";
        a = { ...a, imm: targetPc(a.target) };
    }
    if (R_TABLE[op]) {
        const [funct7, funct3] = R_TABLE[op];
        return u32((funct7 << 25) | (a.rs2 << 20) | (a.rs1 << 15) |
                   (funct3 << 12) | (a.rd << 7) | 0x33);
    }
    if (Object.prototype.hasOwnProperty.call(I_TABLE, op)) {
        checkSigned(a.imm, 12, `${op} immediate`);
        return u32((bits(a.imm, 12) << 20) | (a.rs1 << 15) |
                   (I_TABLE[op] << 12) | (a.rd << 7) | 0x13);
    }
    if (SHIFT_I_TABLE[op]) {
        checkUnsigned(a.imm, 5, `${op} shamt`);
        const [funct7, funct3] = SHIFT_I_TABLE[op];
        return u32((funct7 << 25) | (a.imm << 20) | (a.rs1 << 15) |
                   (funct3 << 12) | (a.rd << 7) | 0x13);
    }
    if (Object.prototype.hasOwnProperty.call(LOAD_TABLE, op)) {
        checkSigned(a.imm, 12, `${op} offset`);
        return u32((bits(a.imm, 12) << 20) | (a.rs1 << 15) |
                   (LOAD_TABLE[op] << 12) | (a.rd << 7) | 0x03);
    }
    if (Object.prototype.hasOwnProperty.call(STORE_TABLE, op)) {
        checkSigned(a.imm, 12, `${op} offset`);
        const imm = bits(a.imm, 12);
        return u32(((imm >>> 5) << 25) | (a.rs2 << 20) | (a.rs1 << 15) |
                   (STORE_TABLE[op] << 12) | ((imm & 0x1f) << 7) | 0x23);
    }
    if (Object.prototype.hasOwnProperty.call(BRANCH_TABLE, op)) {
        const off = targetPc(a.target) - pc;
        checkSigned(off, 13, `${op} offset`);
        if ((off & 1) !== 0) throw new Error(`${op} target desalinhado`);
        const imm = bits(off, 13);
        return u32((((imm >>> 12) & 1) << 31) | (((imm >>> 5) & 0x3f) << 25) |
                   (a.rs2 << 20) | (a.rs1 << 15) | (BRANCH_TABLE[op] << 12) |
                   (((imm >>> 1) & 0xf) << 8) | (((imm >>> 11) & 1) << 7) | 0x63);
    }
    if (op === "jal") {
        const off = targetPc(a.target) - pc;
        checkSigned(off, 21, "jal offset");
        if ((off & 1) !== 0) throw new Error("jal target desalinhado");
        const imm = bits(off, 21);
        return u32((((imm >>> 20) & 1) << 31) | (((imm >>> 1) & 0x3ff) << 21) |
                   (((imm >>> 11) & 1) << 20) | (((imm >>> 12) & 0xff) << 12) |
                   (a.rd << 7) | 0x6f);
    }
    if (op === "jalr") {
        checkSigned(a.imm, 12, "jalr offset");
        return u32((bits(a.imm, 12) << 20) | (a.rs1 << 15) |
                   (a.rd << 7) | 0x67);
    }
    if (op === "lui" || op === "auipc") {
        checkUnsigned(a.imm20, 20, `${op} immediate`);
        return u32((a.imm20 << 12) | (a.rd << 7) | (op === "lui" ? 0x37 : 0x17));
    }
    throw new Error(`operacao sem encoder: ${op}`);
}

const words = program.map(encode);
if (words.length > 512) throw new Error(`programa possui ${words.length} palavras; maximo 512`);

function resolvedArgs(insn) {
    if (insn.op === "addi_label")
        return { ...insn.args, imm: targetPc(insn.args.target) };
    return insn.args;
}
function renderInstruction(insn) {
    const op = insn.op === "addi_label" ? "addi" : insn.op;
    const a = resolvedArgs(insn);
    let body;
    if (R_TABLE[op]) body = `${op} ${ABI[a.rd]},${ABI[a.rs1]},${ABI[a.rs2]}`;
    else if (Object.prototype.hasOwnProperty.call(I_TABLE, op) || SHIFT_I_TABLE[op])
        body = `${op} ${ABI[a.rd]},${ABI[a.rs1]},${a.imm}`;
    else if (Object.prototype.hasOwnProperty.call(LOAD_TABLE, op))
        body = `${op} ${ABI[a.rd]},${a.imm}(${ABI[a.rs1]})`;
    else if (Object.prototype.hasOwnProperty.call(STORE_TABLE, op))
        body = `${op} ${ABI[a.rs2]},${a.imm}(${ABI[a.rs1]})`;
    else if (Object.prototype.hasOwnProperty.call(BRANCH_TABLE, op))
        body = `${op} ${ABI[a.rs1]},${ABI[a.rs2]},${a.target}`;
    else if (op === "jal") body = `jal ${ABI[a.rd]},${a.target}`;
    else if (op === "jalr") body = `jalr ${ABI[a.rd]},${a.imm}(${ABI[a.rs1]})`;
    else body = `${op} ${ABI[a.rd]},0x${a.imm20.toString(16)}`;
    return `    ${body.padEnd(38)}${insn.note ? `# ${insn.note}` : ""}`.trimEnd();
}

let asm = "";
for (const item of asmItems) {
    if (item.kind === "comment") asm += `${item.text}\n`;
    else if (item.kind === "label") asm += `${item.name}:\n`;
    else asm += `${renderInstruction(item.insn)}\n`;
}

const labelRows = [...labels.entries()].sort((a, b) => a[1] - b[1]);
let map = "# rv32i_system_program.map\n";
map += `# instructions=${words.length} bytes=${words.length * 4} imem_percent=${(words.length / 512 * 100).toFixed(2)}\n`;
map += `# alu_signature=0x${hex32(ALU_SIGNATURE)} branch_signature=0x${hex32(BRANCH_SIGNATURE)} memory_signature=0x${hex32(MEMORY_SIGNATURE)}\n`;
map += "# PC        label\n";
for (const [name, index] of labelRows) map += `${hexPc(index * 4)}  ${name}\n`;

// Interpretador sequencial pequeno: valida o software e a codificacao gerada.
function signExtend(value, width) { return (value << (32 - width)) >> (32 - width); }
function loadU16(mem, addr) { return mem[addr] | (mem[addr + 1] << 8); }
function loadU32(mem, addr) {
    return u32(mem[addr] | (mem[addr + 1] << 8) |
               (mem[addr + 2] << 16) | (mem[addr + 3] << 24));
}
function storeU32(mem, addr, value) {
    value = u32(value);
    mem[addr] = value & 0xff; mem[addr + 1] = (value >>> 8) & 0xff;
    mem[addr + 2] = (value >>> 16) & 0xff; mem[addr + 3] = (value >>> 24) & 0xff;
}
function simulate() {
    const reg = new Uint32Array(32);
    const mem = new Uint8Array(2048);
    const seen = new Set();
    let pc = 0;
    let steps = 0;
    let minSp = 0xffffffff;
    while (steps++ < 200000) {
        if ((pc & 3) || (pc >>> 2) >= words.length) throw new Error(`PC invalido 0x${hex32(pc)}`);
        const w = words[pc >>> 2] >>> 0;
        const opcode = w & 0x7f, rd = (w >>> 7) & 31, f3 = (w >>> 12) & 7;
        const rs1 = (w >>> 15) & 31, rs2 = (w >>> 20) & 31, f7 = (w >>> 25) & 0x7f;
        let next = u32(pc + 4), value = 0, write = false, name = "";
        const a = reg[rs1] >>> 0, b = reg[rs2] >>> 0;
        if (opcode === 0x13) {
            const imm = signExtend(w >>> 20, 12);
            write = true;
            if (f3 === 0) { name="ADDI"; value=u32(a+imm); }
            else if (f3 === 1) { name="SLLI"; value=u32(a << ((w>>>20)&31)); }
            else if (f3 === 2) { name="SLTI"; value=s32(a)<imm?1:0; }
            else if (f3 === 3) { name="SLTIU"; value=a<u32(imm)?1:0; }
            else if (f3 === 4) { name="XORI"; value=u32(a ^ u32(imm)); }
            else if (f3 === 5 && ((w>>>30)&1)===0) { name="SRLI"; value=a>>>((w>>>20)&31); }
            else if (f3 === 5) { name="SRAI"; value=u32(s32(a)>>((w>>>20)&31)); }
            else if (f3 === 6) { name="ORI"; value=u32(a|u32(imm)); }
            else if (f3 === 7) { name="ANDI"; value=u32(a&u32(imm)); }
        } else if (opcode === 0x33) {
            write = true;
            if (f3===0 && f7===0) {name="ADD";value=u32(a+b);}
            else if (f3===0) {name="SUB";value=u32(a-b);}
            else if (f3===1) {name="SLL";value=u32(a<<(b&31));}
            else if (f3===2) {name="SLT";value=s32(a)<s32(b)?1:0;}
            else if (f3===3) {name="SLTU";value=a<b?1:0;}
            else if (f3===4) {name="XOR";value=u32(a^b);}
            else if (f3===5 && f7===0) {name="SRL";value=a>>>(b&31);}
            else if (f3===5) {name="SRA";value=u32(s32(a)>>(b&31));}
            else if (f3===6) {name="OR";value=u32(a|b);}
            else if (f3===7) {name="AND";value=u32(a&b);}
        } else if (opcode === 0x03) {
            const imm=signExtend(w>>>20,12), addr=u32(a+imm);
            if (addr>=2048) throw new Error(`LOAD fora da DMEM 0x${hex32(addr)}`);
            write=true;
            if (f3===0) {name="LB";value=u32(signExtend(mem[addr],8));}
            else if (f3===1) {name="LH";if(addr&1)throw new Error("LH desalinhado");value=u32(signExtend(loadU16(mem,addr),16));}
            else if (f3===2) {name="LW";if(addr&3)throw new Error("LW desalinhado");value=loadU32(mem,addr);}
            else if (f3===4) {name="LBU";value=mem[addr];}
            else if (f3===5) {name="LHU";if(addr&1)throw new Error("LHU desalinhado");value=loadU16(mem,addr);}
        } else if (opcode === 0x23) {
            const imm=signExtend((((w>>>25)&0x7f)<<5)|((w>>>7)&31),12), addr=u32(a+imm);
            if (addr>=2048) throw new Error(`STORE fora da DMEM 0x${hex32(addr)}`);
            if(f3===0){name="SB";mem[addr]=b&0xff;}
            else if(f3===1){name="SH";if(addr&1)throw new Error("SH desalinhado");mem[addr]=b&255;mem[addr+1]=(b>>>8)&255;}
            else if(f3===2){name="SW";if(addr&3)throw new Error("SW desalinhado");storeU32(mem,addr,b);}
        } else if (opcode === 0x63) {
            const imm=signExtend((((w>>>31)&1)<<12)|(((w>>>7)&1)<<11)|(((w>>>25)&0x3f)<<5)|(((w>>>8)&15)<<1),13);
            let take=false;
            if(f3===0){name="BEQ";take=a===b;} else if(f3===1){name="BNE";take=a!==b;}
            else if(f3===4){name="BLT";take=s32(a)<s32(b);} else if(f3===5){name="BGE";take=s32(a)>=s32(b);}
            else if(f3===6){name="BLTU";take=a<b;} else if(f3===7){name="BGEU";take=a>=b;}
            if(take)next=u32(pc+imm);
        } else if (opcode === 0x37) {name="LUI";write=true;value=w&0xfffff000;}
        else if (opcode === 0x17) {name="AUIPC";write=true;value=u32(pc+(w&0xfffff000));}
        else if (opcode === 0x6f) {
            name="JAL";write=true;value=u32(pc+4);
            const imm=signExtend((((w>>>31)&1)<<20)|(((w>>>12)&255)<<12)|(((w>>>20)&1)<<11)|(((w>>>21)&0x3ff)<<1),21);
            next=u32(pc+imm);
        } else if (opcode === 0x67) {
            name="JALR";write=true;value=u32(pc+4);
            next=u32((a+signExtend(w>>>20,12))&~1);
        } else throw new Error(`opcode nao suportado 0x${opcode.toString(16)} em PC 0x${hexPc(pc)}`);
        if (!name) throw new Error(`encoding invalido 0x${hex32(w)} em PC 0x${hexPc(pc)}`);
        seen.add(name);
        if(write && rd!==0)reg[rd]=u32(value);
        reg[0]=0;
        pc=next;
        if(reg[R.sp]!==0 && reg[R.sp]<minSp)minSp=reg[R.sp];
        const status=loadU32(mem,0x1f0);
        if(status!==0) return {reg,mem,seen,steps,minSp,status};
    }
    throw new Error("timeout no interpretador local");
}

const result = simulate();
const expectedIsa = ["ADDI","SLLI","SLTI","SLTIU","XORI","SRLI","SRAI","ORI","ANDI",
    "ADD","SUB","SLL","SLT","SLTU","XOR","SRL","SRA","OR","AND",
    "LB","LH","LW","LBU","LHU","SB","SH","SW","BEQ","BNE","BLT","BGE","BLTU","BGEU",
    "LUI","AUIPC","JAL","JALR"];
const missing = expectedIsa.filter(name => !result.seen.has(name));
if (missing.length) throw new Error(`instrucoes nao executadas: ${missing.join(", ")}`);
function expectWord(addr, expected, name) {
    const actual=loadU32(result.mem,addr);
    if(actual!==u32(expected))throw new Error(`${name}: 0x${hex32(actual)} != 0x${hex32(expected)}`);
}
expectWord(0x1f0,PASS_STATUS,"status"); expectWord(0x1f4,0,"error"); expectWord(0x1f8,0x800,"sp snapshot");
expectWord(0x180,20,"sum"); expectWord(0x184,-3,"min"); expectWord(0x188,12,"max");
expectWord(0x18c,3,"search found"); expectWord(0x190,-1,"search missing"); expectWord(0x194,11,"dot");
expectWord(0x198,13,"checksum"); expectWord(0x19c,BRANCH_SIGNATURE,"branch signature");
expectWord(0x1a0,ALU_SIGNATURE,"ALU signature"); expectWord(0x1a4,MEMORY_SIGNATURE,"memory signature");
expectWord(0x1a8,targetPc("pc_probe_auipc"),"pc probe"); expectWord(0x1ac,20,"load-store copy");
for (const [addr,val] of [[0x100,-3],[0x104,4],[0x108,7],[0x10c,12],[0x120,2],[0x124,5],[0x128,-1],[0x12c,6]])
    expectWord(addr,val,`memory 0x${addr.toString(16)}`);
expectWord(0x1b0,0x80ff7f01,"byte lanes"); expectWord(0x1b4,0x80017fff,"halfword lanes");
if(result.reg[R.sp]!==0x800)throw new Error(`sp final 0x${hex32(result.reg[R.sp])}`);

fs.mkdirSync(SW_DIR,{recursive:true}); fs.mkdirSync(MEM_DIR,{recursive:true}); fs.mkdirSync(TB_DIR,{recursive:true});
fs.writeFileSync(path.join(SW_DIR,"rv32i_system_program.s"),asm);
fs.writeFileSync(path.join(MEM_DIR,"rv32i_system_program.hex"),words.map(hex32).join("\n")+"\n");
fs.writeFileSync(path.join(MEM_DIR,"rv32i_system_program.map"),map);
const symbols = [
    "// Gerado por tools/gen_rv32i_system_program.js. Nao editar manualmente.",
    `localparam integer PROGRAM_WORDS = ${words.length};`,
    `localparam integer PROGRAM_BYTES = ${words.length*4};`,
    `localparam logic [31:0] BINARY_SEARCH_PC = 32'h${hex32(targetPc("binary_search_recursive"))};`,
    `localparam logic [31:0] BINARY_SEARCH_END_PC = 32'h${hex32(targetPc("checksum8"))};`,
    `localparam logic [31:0] LOAD_STORE_COPY_LOAD_PC = 32'h${hex32(targetPc("load_store_copy_load"))};`,
    `localparam logic [31:0] PC_PROBE_AUIPC_PC = 32'h${hex32(targetPc("pc_probe_auipc"))};`,
    `localparam logic [31:0] ALU_SIGNATURE = 32'h${hex32(ALU_SIGNATURE)};`,
    `localparam logic [31:0] BRANCH_SIGNATURE = 32'h${hex32(BRANCH_SIGNATURE)};`,
    `localparam logic [31:0] MEMORY_SIGNATURE = 32'h${hex32(MEMORY_SIGNATURE)};`,
    `localparam logic [31:0] PASS_STATUS = 32'h${hex32(PASS_STATUS)};`,
    `localparam logic [31:0] FAIL_STATUS = 32'h${hex32(FAIL_STATUS)};`,
    ""
].join("\n");
fs.writeFileSync(path.join(TB_DIR,"rv32i_system_program_symbols.svh"),symbols);

console.log(`Gerado: ${words.length} instrucoes, ${words.length*4} bytes, ${(words.length/512*100).toFixed(2)}% da IMEM`);
console.log(`Validacao ISA local: PASS em ${result.steps} instrucoes; menor sp=0x${hex32(result.minSp)}`);
console.log(`Assinaturas: ALU=0x${hex32(ALU_SIGNATURE)} branch=0x${hex32(BRANCH_SIGNATURE)} memory=0x${hex32(MEMORY_SIGNATURE)}`);
console.log(`pc_probe AUIPC: 0x${hex32(targetPc("pc_probe_auipc"))}`);
