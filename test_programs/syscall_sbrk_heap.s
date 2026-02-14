# Syscall 9 heap allocation behavior.
# Confirms 4-byte alignment and basic heap read/write via lb/sb.

.text
.globl main

main:
    li   $a0, 1
    li   $v0, 9
    syscall
    move $s0, $v0

    li   $a0, 3
    li   $v0, 9
    syscall
    move $s1, $v0

    subu $t0, $s1, $s0
    li   $v0, 1
    move $a0, $t0
    syscall
    jal  print_newline

    li   $t1, 65
    sb   $t1, 0($s0)
    li   $t2, 66
    sb   $t2, 0($s1)

    li   $v0, 11
    lb   $a0, 0($s0)
    syscall
    lb   $a0, 0($s1)
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
