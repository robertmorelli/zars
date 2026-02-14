# Self-modifying decode probe for SPECIAL2 madd/maddu/msub/msubu opcodes.

.text
.globl main
main:
    li   $s0, 6
    li   $s1, 5

    # madd  $s0, $s1
    li   $t8, 0x72110000
    la   $t9, slot_madd
    sw   $t8, 0($t9)

    # mflo  $t0
    li   $t8, 0x00004012
    la   $t9, slot_mflo_1
    sw   $t8, 0($t9)

    # maddu $s0, $s1
    li   $t8, 0x72110001
    la   $t9, slot_maddu
    sw   $t8, 0($t9)

    # mflo  $t1
    li   $t8, 0x00004812
    la   $t9, slot_mflo_2
    sw   $t8, 0($t9)

    # msub  $s0, $s1
    li   $t8, 0x72110004
    la   $t9, slot_msub
    sw   $t8, 0($t9)

    # mflo  $t2
    li   $t8, 0x00005012
    la   $t9, slot_mflo_3
    sw   $t8, 0($t9)

    # msubu $s0, $s1
    li   $t8, 0x72110005
    la   $t9, slot_msubu
    sw   $t8, 0($t9)

    # mflo  $t3
    li   $t8, 0x00005812
    la   $t9, slot_mflo_4
    sw   $t8, 0($t9)

    # Reset HI/LO to zero before patched accumulation sequence.
    mtlo $zero
    mthi $zero

    j    slot_madd

slot_madd:
    nop
slot_mflo_1:
    nop
slot_maddu:
    nop
slot_mflo_2:
    nop
slot_msub:
    nop
slot_mflo_3:
    nop
slot_msubu:
    nop
slot_mflo_4:
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

    li   $v0, 10
    syscall
