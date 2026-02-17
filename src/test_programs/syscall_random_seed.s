# Random syscalls with explicit seed for reproducibility.

.text
.globl main

main:
    # Seed stream 7 with fixed seed.
    li   $v0, 40
    li   $a0, 7
    li   $a1, 123456
    syscall

    # Random int (service 41) result in $a0.
    li   $v0, 41
    li   $a0, 7
    syscall
    move $t0, $a0
    li   $v0, 1
    move $a0, $t0
    syscall
    jal  print_newline

    # Random int range [0,100) (service 42) result in $a0.
    li   $v0, 42
    li   $a0, 7
    li   $a1, 100
    syscall
    move $t1, $a0
    li   $v0, 1
    move $a0, $t1
    syscall
    jal  print_newline

    # Random float [0,1) in $f0 (service 43).
    li   $v0, 43
    li   $a0, 7
    syscall
    mov.s $f12, $f0
    li   $v0, 2
    syscall
    jal  print_newline

    # Random double [0,1) in $f0 (service 44).
    li   $v0, 44
    li   $a0, 7
    syscall
    mov.d $f12, $f0
    li   $v0, 3
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
