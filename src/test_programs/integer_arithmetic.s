# Integer arithmetic and HI/LO behavior.

.text
.globl main

main:
    li $t0, 40
    li $t1, 2

    add  $t2, $t0, $t1      # 42
    sub  $t3, $t0, $t1      # 38

    mult $t0, $t1
    mflo $t4                # 80

    li   $t5, 85
    li   $t6, 9
    div  $t5, $t6
    mflo $t7                # 9
    mfhi $s0                # 4

    slt  $s1, $t1, $t0      # 1
    sltu $s2, $zero, $t3    # 1

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

    move $a0, $t7
    li   $v0, 1
    syscall
    jal  print_newline

    move $a0, $s0
    li   $v0, 1
    syscall
    jal  print_newline

    move $a0, $s1
    li   $v0, 1
    syscall
    jal  print_newline

    move $a0, $s2
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
