#
# Additional pseudo-op text layout probe.
# This case extends `pseudo_layout_counts.s` with more compare/set/branch and
# register-pair pseudo instructions to validate label-address byte deltas.
#

.text
main:
    la $t0, sne_rr_after
    la $t1, sne_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, sge_rr_after
    la $t1, sge_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, sgt_rr_after
    la $t1, sgt_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, sle_rr_after
    la $t1, sle_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, sgtu_rr_after
    la $t1, sgtu_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, bgt_rr_after
    la $t1, bgt_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, bgt_ri_after
    la $t1, bgt_ri_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, ble_rr_after
    la $t1, ble_rr_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, ble_ri_after
    la $t1, ble_ri_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, mtc1d_after
    la $t1, mtc1d_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, mulu_i16_after
    la $t1, mulu_i16_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 11
    li $a0, 10
    syscall

    la $t0, mulu_i32_after
    la $t1, mulu_i32_before
    subu $a0, $t0, $t1
    li $v0, 1
    syscall
    li $v0, 10
    syscall

sne_rr_before:
    sne $s0, $s1, $s2
sne_rr_after:

sge_rr_before:
    sge $s0, $s1, $s2
sge_rr_after:

sgt_rr_before:
    sgt $s0, $s1, $s2
sgt_rr_after:

sle_rr_before:
    sle $s0, $s1, $s2
sle_rr_after:

sgtu_rr_before:
    sgtu $s0, $s1, $s2
sgtu_rr_after:

bgt_rr_before:
    bgt $s0, $s1, bgt_rr_target
bgt_rr_target:
bgt_rr_after:

bgt_ri_before:
    bgt $s0, 5, bgt_ri_target
bgt_ri_target:
bgt_ri_after:

ble_rr_before:
    ble $s0, $s1, ble_rr_target
ble_rr_target:
ble_rr_after:

ble_ri_before:
    ble $s0, 5, ble_ri_target
ble_ri_target:
ble_ri_after:

mtc1d_before:
    mtc1.d $s0, $f2
mtc1d_after:

mulu_i16_before:
    mulu $s0, $s1, 5
mulu_i16_after:

mulu_i32_before:
    mulu $s0, $s1, 100000
mulu_i32_after:
