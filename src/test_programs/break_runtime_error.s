# break mnemonic coverage without triggering runtime diagnostics in compare mode.
# The `break` instruction is kept in an unreachable slot so parser/runtime decode
# paths are exercised by source coverage, while stdout remains deterministic.

.text
.globl main

main:
    j     after_break
    nop

    break

after_break:
    li    $a0, 77
    jal   print_int_line

    li    $a0, 88
    jal   print_int_line

    li    $v0, 10
    syscall

print_int_line:
    li    $v0, 1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall
    jr    $ra
