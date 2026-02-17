# Delayed branch nesting probe.
# The delay slot itself contains a taken branch. MARS keeps the original
# target but extends the delay slot by one instruction.

.text
.globl main

main:
    li   $s0, 0
    li   $t0, 1
    li   $t1, 1

    beq  $t0, $t1, outer_target
    beq  $t0, $t1, inner_target
    li   $s0, 7

inner_target:
    li   $s0, 99
    j    done

outer_target:
    li   $v0, 1
    move $a0, $s0
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

done:
    li   $v0, 10
    syscall
