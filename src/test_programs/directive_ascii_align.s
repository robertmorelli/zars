# Data directive coverage for .ascii and .align.
# Uses address deltas plus data load to validate emitted layout.

.data
prefix: .ascii "AB"
.align 2
value_word: .word 0x11223344

.text
.globl main

main:
    la   $t0, prefix
    la   $t1, value_word
    subu $t2, $t1, $t0

    li   $v0, 1
    move $a0, $t2
    syscall
    jal  print_newline

    lw   $a0, 0($t1)
    li   $v0, 34
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
