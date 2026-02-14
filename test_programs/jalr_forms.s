# jalr single-operand and two-operand forms.
# The test prints a deterministic total from both calls.

.text
.globl main

main:
    li   $s0, 0

    # jalr rs form: link register is $ra.
    la   $t0, target_one
    jalr $t0
    addiu $s0, $s0, 1

    # jalr rd, rs form: link register is explicit.
    la   $t1, target_two
    jalr $s5, $t1
    addiu $s0, $s0, 2

    li   $v0, 1
    move $a0, $s0
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

target_one:
    addiu $s0, $s0, 10
    jr    $ra

target_two:
    addiu $s0, $s0, 20
    jr    $s5

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
