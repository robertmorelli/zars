# Self-modifying code test.
# Rewrites a NOP in text to a SYSCALL with non-zero code field.
# Run with command option: smc

.text
.globl main

main:
    # Patch do_syscall to instruction 0x02AF378C:
    # opcode=0, code=0xABCDE, funct=0x0C (syscall).
    li   $t0, 0x02AF378C
    la   $t1, do_syscall
    sw   $t0, 0($t1)

    li   $v0, 1
    li   $a0, 111

do_syscall:
    nop

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
