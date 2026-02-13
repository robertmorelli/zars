# Shared macros for MARS test programs.

.macro print_newline
    li $v0, 11
    li $a0, 10
    syscall
.end_macro

.macro print_string (%label)
    li $v0, 4
    la $a0, %label
    syscall
.end_macro

.macro print_int_reg (%reg)
    li $v0, 1
    move $a0, %reg
    syscall
.end_macro

.macro add_three (%dst, %lhs, %mid, %rhs)
    addu %dst, %lhs, %mid
    addu %dst, %dst, %rhs
.end_macro
