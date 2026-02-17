# Time service (30) writes low/high milliseconds into $a0/$a1.
# This program prints 1 when at least one of those words is non-zero.

.text
main:
    li $a0, 0
    li $a1, 0
    li $v0, 30
    syscall

    or   $t0, $a0, $a1
    sltu $t1, $zero, $t0

    li $v0, 1
    move $a0, $t1
    syscall

    li $v0, 10
    syscall
