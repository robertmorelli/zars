# Directive compatibility probe for parser behavior:
# - ignored directives .globl/.extern

.data
message: .asciiz "compat"

.text
.globl main
.extern external_symbol,4
main:
    la $a0, message
    li $v0, 4
    syscall

    li $v0, 10
    syscall
