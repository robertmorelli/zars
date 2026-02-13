# Program arguments via command-mode option: pa arg1 arg2 ...

.text
.globl main

main:
    # argc from $a0
    move $t0, $a0

    li   $v0, 1
    move $a0, $t0
    syscall
    jal  print_newline

    beq  $t0, $zero, done

    # argv[0]
    lw   $t1, 0($a1)
    li   $v0, 4
    move $a0, $t1
    syscall
    jal  print_newline

    # argv[argc - 1]
    addiu $t2, $t0, -1
    sll   $t2, $t2, 2
    addu  $t3, $a1, $t2
    lw    $t4, 0($t3)
    li    $v0, 4
    move  $a0, $t4
    syscall
    jal   print_newline

done:
    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
