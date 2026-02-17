# Coprocessor 1 arithmetic, compare, and conversion.

.data
value_a: .float 1.5
value_b: .float 2.25
value_c: .double 3.5
value_d: .double 0.5

.text
.globl main

main:
    l.s   $f0, value_a
    l.s   $f2, value_b
    add.s $f4, $f0, $f2      # 3.75
    mul.s $f6, $f0, $f2      # 3.375

    mov.s $f12, $f4
    li    $v0, 2
    syscall
    jal   print_newline

    mov.s $f12, $f6
    li    $v0, 2
    syscall
    jal   print_newline

    l.d   $f8, value_c
    l.d   $f10, value_d
    sub.d $f12, $f8, $f10    # 3.0
    li    $v0, 3
    syscall
    jal   print_newline

    c.eq.s $f0, $f0
    bc1t  compare_true

    li    $a0, 0
    li    $v0, 1
    syscall
    j     done

compare_true:
    li    $a0, 1
    li    $v0, 1
    syscall

done:
    jal   print_newline
    li    $v0, 10
    syscall

print_newline:
    li    $v0, 11
    li    $a0, 10
    syscall
    jr    $ra
