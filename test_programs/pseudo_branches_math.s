# Pseudo-op coverage for arithmetic/compare/branch aliases.
# Covers: abs, bge, bgt, ble, bgeu, bgtu, bleu, bltu,
# seq, sne, sge, sgt, sle, sgeu, sgtu, sleu, mulu, rem, remu, rol, ror.

.text
main:
    li    $t0, -5
    abs   $t1, $t0

    li    $t2, 10
    li    $t3, 3
    mulu  $t4, $t2, $t3
    rem   $t5, $t2, $t3
    remu  $t6, $t2, $t3

    li    $t7, 1
    rol   $s0, $t7, 8
    ror   $s1, $s0, 8

    li    $s2, 0
    bge   $t2, $t3, bge_ok
    li    $s2, 99
bge_ok:

    li    $s3, 0
    bgt   $t2, $t3, bgt_ok
    li    $s3, 99
bgt_ok:

    li    $s4, 0
    ble   $t3, $t2, ble_ok
    li    $s4, 99
ble_ok:

    li    $s5, 0
    bgeu  $t2, $t3, bgeu_ok
    li    $s5, 99
bgeu_ok:

    li    $s6, 0
    bgtu  $t2, $t3, bgtu_ok
    li    $s6, 99
bgtu_ok:

    li    $s7, 0
    bleu  $t3, $t2, bleu_ok
    li    $s7, 99
bleu_ok:

    li    $v1, 0
    bltu  $t3, $t2, bltu_ok
    li    $v1, 99
bltu_ok:

    seq   $a0, $t2, $t2
    sne   $a1, $t2, $t3
    sge   $a2, $t2, $t3
    sgt   $a3, $t2, $t3
    sle   $k0, $t3, $t2
    sgeu  $k1, $t2, $t3
    sgtu  $gp, $t2, $t3
    sleu  $fp, $t3, $t2

    addu  $t8, $t1, $t4
    addu  $t8, $t8, $t5
    addu  $t8, $t8, $t6
    addu  $t8, $t8, $s0
    addu  $t8, $t8, $s1
    addu  $t8, $t8, $s2
    addu  $t8, $t8, $s3
    addu  $t8, $t8, $s4
    addu  $t8, $t8, $s5
    addu  $t8, $t8, $s6
    addu  $t8, $t8, $s7
    addu  $t8, $t8, $v1
    addu  $t8, $t8, $a0
    addu  $t8, $t8, $a1
    addu  $t8, $t8, $a2
    addu  $t8, $t8, $a3
    addu  $t8, $t8, $k0
    addu  $t8, $t8, $k1
    addu  $t8, $t8, $gp
    addu  $t8, $t8, $fp

    li    $v0, 1
    move  $a0, $t8
    syscall

    li    $v0, 10
    syscall
