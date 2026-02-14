# mulou coverage for both reg/reg and reg/immediate pseudo expansion forms.
# This case intentionally stays non-trapping so compare-mode stdout remains clean.

.text
.globl main

main:
    li    $t0, 30000
    li    $t1, 2
    mulou $t2, $t0, $t1
    move  $a0, $t2
    jal   print_int_line

    mulou $t3, $t0, 3
    move  $a0, $t3
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
