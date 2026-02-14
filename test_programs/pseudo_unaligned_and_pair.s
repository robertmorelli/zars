# Pseudo-op coverage for memory/register-pair aliases.
# Covers: ulh, ulhu, ulw, ush, usw, ld, sd, mfc1.d, mtc1.d.

.data
word0:    .word 0x11223344
pair_src: .word 0x89abcdef, 0x01234567
.align 3
pair_dst: .space 8
dbl:      .double 3.5

.text
main:
    la    $t0, word0
    ulw   $t1, 0($t0)
    ulh   $t2, 0($t0)
    ulhu  $t3, 0($t0)

    li    $t4, 0x55667788
    usw   $t4, 0($t0)
    ush   $t4, 1($t0)
    ulw   $t5, 0($t0)

    la    $t6, pair_src
    ld    $s0, 0($t6)
    la    $t7, pair_dst
    sd    $s0, 0($t7)
    ulw   $s2, 0($t7)
    ulw   $s3, 4($t7)

    l.d   $f4, dbl
    mfc1.d $s4, $f4
    mtc1.d $s4, $f6
    s.d   $f6, pair_dst
    ulw   $s6, 0($t7)
    ulw   $s7, 4($t7)

    li    $v0, 34
    move  $a0, $t1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $t2
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $t3
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $t5
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s0
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s2
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s3
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s6
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 34
    move  $a0, $s7
    syscall

    li    $v0, 10
    syscall
