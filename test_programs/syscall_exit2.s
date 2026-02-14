# Exit2 (17) should terminate immediately without trailing newline output.

.text
main:
    li $a0, 60
    li $v0, 17
    syscall

    # Unreachable if syscall 17 parity is correct.
    li $v0, 1
    li $a0, 999
    syscall
