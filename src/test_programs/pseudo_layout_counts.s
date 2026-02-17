# Pseudo-op text layout probe.
# This verifies that label addresses advance by the same byte counts as MARS for
# selected pseudo-op families that expand to multiple basic instructions.

.text
main:
    la   $t0, add_small_after
    la   $t1, add_small_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, add_large_after
    la   $t1, add_large_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, seq_rr_after
    la   $t1, seq_rr_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, seq_ri_after
    la   $t1, seq_ri_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, bge_rr_after
    la   $t1, bge_rr_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, bge_ri_after
    la   $t1, bge_ri_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, rol_rr_after
    la   $t1, rol_rr_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, rol_ri_after
    la   $t1, rol_ri_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, mfc1d_after
    la   $t1, mfc1d_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, mulu_after
    la   $t1, mulu_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 10
    syscall

add_small_before:
    add  $s0, $s1, 5
add_small_after:

add_large_before:
    add  $s0, $s1, 100000
add_large_after:

seq_rr_before:
    seq  $s0, $s1, $s2
seq_rr_after:

seq_ri_before:
    seq  $s0, $s1, 5
seq_ri_after:

bge_rr_before:
    bge  $s0, $s1, bge_rr_target
bge_rr_target:
bge_rr_after:

bge_ri_before:
    bge  $s0, 100000, bge_ri_target
bge_ri_target:
bge_ri_after:

rol_rr_before:
    rol  $s0, $s1, $s2
rol_rr_after:

rol_ri_before:
    rol  $s0, $s1, 3
rol_ri_after:

mfc1d_before:
    mfc1.d $s0, $f2
mfc1d_after:

mulu_before:
    mulu $s0, $s1, $s2
mulu_after:
