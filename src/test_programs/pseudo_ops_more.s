# Additional pseudo-op coverage:
# b, beqz, bnez, s.s, s.d, negu, subi, subiu.

.data
fval:    .float 1.5
fstore:  .space 4
dval:    .double 2.5
dstore:  .space 8

.text
main:
    li    $t0, 10
    subi  $t1, $t0, 3
    subiu $t2, $t0, 4

    li    $t3, 5
    negu  $t4, $t3

    beqz  $zero, branch_a
    li    $s0, 99
branch_a:
    li    $s0, 0

    b     after_b
    li    $s1, 99
after_b:
    li    $s1, 0

    li    $s2, 1
    bnez  $s2, branch_c
    li    $s3, 99
branch_c:
    li    $s3, 0

    l.s   $f0, fval
    s.s   $f0, fstore

    l.d   $f2, dval
    s.d   $f2, dstore

    lw    $s4, fstore
    la    $t7, dstore
    lw    $s5, 0($t7)
    lw    $s6, 4($t7)

    li    $v0, 1
    move  $a0, $t1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 1
    move  $a0, $t2
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 1
    move  $a0, $t4
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 1
    move  $a0, $s0
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 1
    move  $a0, $s1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 1
    move  $a0, $s3
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s4
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s5
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s6
    syscall
    li    $v0, 10
    syscall
