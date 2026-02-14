# Self-modifying decode probe for patched integer/HI-LO core instruction encodings.
# Exercises R-type math/compare/shift, SPECIAL2 clz/clo/mul, and I-type slti/sltiu.

.text
.globl main
main:
    li   $s0, 16
    li   $s1, 3
    li   $s2, -4

    # add  $t0, $s0, $s1
    li   $t8, 0x02114020
    la   $t9, slot_add
    sw   $t8, 0($t9)

    # sub  $t1, $s0, $s1
    li   $t8, 0x02114822
    la   $t9, slot_sub
    sw   $t8, 0($t9)

    # slt  $t2, $s2, $s1
    li   $t8, 0x0251502A
    la   $t9, slot_slt
    sw   $t8, 0($t9)

    # sltu $t3, $s2, $s1
    li   $t8, 0x0251582B
    la   $t9, slot_sltu
    sw   $t8, 0($t9)

    # sllv $t4, $s1, $s0
    li   $t8, 0x02116004
    la   $t9, slot_sllv
    sw   $t8, 0($t9)

    # srlv $t5, $s0, $s1
    li   $t8, 0x02306806
    la   $t9, slot_srlv
    sw   $t8, 0($t9)

    # srav $t6, $s2, $s1
    li   $t8, 0x02327007
    la   $t9, slot_srav
    sw   $t8, 0($t9)

    # slti $t7, $s2, -1
    li   $t8, 0x2A4FFFFF
    la   $t9, slot_slti
    sw   $t8, 0($t9)

    # sltiu $a0, $s2, 1
    li   $t8, 0x2E440001
    la   $t9, slot_sltiu
    sw   $t8, 0($t9)

    # mult $s0, $s1
    li   $t8, 0x02110018
    la   $t9, slot_mult
    sw   $t8, 0($t9)

    # mflo $a1
    li   $t8, 0x00002812
    la   $t9, slot_mflo_after_mult
    sw   $t8, 0($t9)

    # div $s0, $s1
    li   $t8, 0x0211001A
    la   $t9, slot_div
    sw   $t8, 0($t9)

    # mfhi $a2
    li   $t8, 0x00003010
    la   $t9, slot_mfhi_after_div
    sw   $t8, 0($t9)

    # mthi $s2
    li   $t8, 0x02400011
    la   $t9, slot_mthi
    sw   $t8, 0($t9)

    # mfhi $a3
    li   $t8, 0x00003810
    la   $t9, slot_mfhi_after_mthi
    sw   $t8, 0($t9)

    # mtlo $s1
    li   $t8, 0x02200013
    la   $t9, slot_mtlo
    sw   $t8, 0($t9)

    # mflo $v1
    li   $t8, 0x00001812
    la   $t9, slot_mflo_after_mtlo
    sw   $t8, 0($t9)

    # clz $v0, $s0
    li   $t8, 0x72001020
    la   $t9, slot_clz
    sw   $t8, 0($t9)

    # clo $v1, $s2
    li   $t8, 0x72401821
    la   $t9, slot_clo
    sw   $t8, 0($t9)

    # mul $s3, $s0, $s1
    li   $t8, 0x72119802
    la   $t9, slot_mul
    sw   $t8, 0($t9)

    j    slot_add

slot_add:
    nop
slot_sub:
    nop
slot_slt:
    nop
slot_sltu:
    nop
slot_sllv:
    nop
slot_srlv:
    nop
slot_srav:
    nop
slot_slti:
    nop
slot_sltiu:
    nop
slot_mult:
    nop
slot_mflo_after_mult:
    nop
slot_div:
    nop
slot_mfhi_after_div:
    nop
slot_mthi:
    nop
slot_mfhi_after_mthi:
    nop
slot_mtlo:
    nop
slot_mflo_after_mtlo:
    nop
slot_clz:
    nop
slot_clo:
    nop
slot_mul:
    nop

    li   $v0, 1
    move $a0, $t0
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t2
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t3
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t4
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t5
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t6
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $t7
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $a1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $a2
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $a3
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $v1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $s3
    syscall

    li   $v0, 10
    syscall
