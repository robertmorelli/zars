# Branch/jump/jal/jr control-flow test.

.text
.globl main

main:
    li   $t0, 1
    li   $t1, 5
    li   $s0, 0

loop:
    beq  $t0, $t1, loop_last
    addu $s0, $s0, $t0
    addiu $t0, $t0, 1
    j    loop

loop_last:
    addu $s0, $s0, $t1      # sum(1..5) = 15

    jal  triple_accumulator  # 45 in $v0

    move $a0, $v0
    li   $v0, 1
    syscall

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall

triple_accumulator:
    addu $v0, $s0, $s0
    addu $v0, $v0, $s0
    jr   $ra
