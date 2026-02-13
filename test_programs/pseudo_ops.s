# Pseudo-instruction and pseudo-branch coverage.

.data
message_ok: .asciiz "pseudo-ok"

.text
.globl main

main:
    li   $t0, 10
    li   $t1, 20

    blt  $t0, $t1, is_less
    li   $a0, 999
    li   $v0, 1
    syscall
    j    done

is_less:
    move $t2, $t1
    neg  $t3, $t0
    not  $t4, $zero

    la   $a0, message_ok
    li   $v0, 4
    syscall
    jal  print_newline

    move $a0, $t2
    li   $v0, 1
    syscall
    jal  print_newline

    move $a0, $t3
    li   $v0, 1
    syscall
    jal  print_newline

    move $a0, $t4
    li   $v0, 1
    syscall
    jal  print_newline

done:
    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
