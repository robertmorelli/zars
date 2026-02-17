# Negative test: unaligned load should raise runtime exception.

.data
words: .word 1, 2

.text
.globl main

main:
    la   $t0, words
    addiu $t0, $t0, 2
    lw   $t1, 0($t0)      # Address error expected.

    li   $v0, 10
    syscall
