# Midi and sleep services in command-mode parity checks.
# 31 and 33 should not alter architectural state visible to this program,
# and 32 is exercised with a minimal sleep duration.

.text
main:
    li $a0, 60
    li $a1, 1
    li $a2, 0
    li $a3, 100
    li $v0, 31
    syscall

    li $a0, 1
    li $v0, 32
    syscall

    li $a0, 60
    li $a1, 1
    li $a2, 0
    li $a3, 100
    li $v0, 33
    syscall

    li $v0, 1
    li $a0, 123
    syscall

    li $v0, 10
    syscall
