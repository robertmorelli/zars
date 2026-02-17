# Bitwise ops plus logical and arithmetic shifts.

.text
.globl main

main:
    li  $t0, 0x0f0f00ff
    li  $t1, 0x00ff0f0f

    and $t2, $t0, $t1
    or  $t3, $t0, $t1
    xor $t4, $t0, $t1
    nor $t5, $t0, $t1

    sll $t6, $t1, 4
    srl $t7, $t1, 8

    li  $s0, -16
    sra $s1, $s0, 2

    # Print hex values from logical/bitwise ops.
    move $a0, $t2
    li   $v0, 34
    syscall
    jal  print_newline

    move $a0, $t3
    li   $v0, 34
    syscall
    jal  print_newline

    move $a0, $t4
    li   $v0, 34
    syscall
    jal  print_newline

    move $a0, $t5
    li   $v0, 34
    syscall
    jal  print_newline

    move $a0, $t6
    li   $v0, 34
    syscall
    jal  print_newline

    move $a0, $t7
    li   $v0, 34
    syscall
    jal  print_newline

    # Signed result from arithmetic shift.
    move $a0, $s1
    li   $v0, 1
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
