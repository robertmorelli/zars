# Syscalls 6 and 7 read float/double into coprocessor 1.
# Output uses services 2 and 3 to mirror MARS print paths.

.text
.globl main

main:
    li    $v0, 6
    syscall
    mov.s $f12, $f0
    li    $v0, 2
    syscall
    jal   print_newline

    li    $v0, 7
    syscall
    mov.d $f12, $f0
    li    $v0, 3
    syscall
    jal   print_newline

    li    $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
