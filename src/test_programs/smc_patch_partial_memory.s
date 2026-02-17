# Self-modifying decode probe for patched byte/halfword/partial-word memory opcodes.

.data
src_word: .word 0x11223344
dst_word: .word 0

.text
.globl main
main:
    la   $s0, src_word
    la   $s1, dst_word

    # lb   $t0, 0($s0)
    li   $t8, 0x82080000
    la   $t9, slot_lb
    sw   $t8, 0($t9)

    # lbu  $t1, 1($s0)
    li   $t8, 0x92090001
    la   $t9, slot_lbu
    sw   $t8, 0($t9)

    # lh   $t2, 0($s0)
    li   $t8, 0x860A0000
    la   $t9, slot_lh
    sw   $t8, 0($t9)

    # lhu  $t3, 0($s0)
    li   $t8, 0x960B0000
    la   $t9, slot_lhu
    sw   $t8, 0($t9)

    # ll   $t4, 0($s0)
    li   $t8, 0xC20C0000
    la   $t9, slot_ll
    sw   $t8, 0($t9)

    # sc   $t4, 0($s1)
    li   $t8, 0xE22C0000
    la   $t9, slot_sc
    sw   $t8, 0($t9)

    # lwl  $t5, 1($s0)
    li   $t8, 0x8A0D0001
    la   $t9, slot_lwl
    sw   $t8, 0($t9)

    # lwr  $t5, 2($s0)
    li   $t8, 0x9A0D0002
    la   $t9, slot_lwr
    sw   $t8, 0($t9)

    # swl  $t5, 1($s1)
    li   $t8, 0xAA2D0001
    la   $t9, slot_swl
    sw   $t8, 0($t9)

    # swr  $t5, 2($s1)
    li   $t8, 0xBA2D0002
    la   $t9, slot_swr
    sw   $t8, 0($t9)

    # sb   $t1, 0($s1)
    li   $t8, 0xA2290000
    la   $t9, slot_sb
    sw   $t8, 0($t9)

    # sh   $t2, 2($s1)
    li   $t8, 0xA62A0002
    la   $t9, slot_sh
    sw   $t8, 0($t9)

    j    slot_lb

slot_lb:
    nop
slot_lbu:
    nop
slot_lh:
    nop
slot_lhu:
    nop
slot_ll:
    nop
slot_sc:
    nop
slot_lwl:
    nop
slot_lwr:
    nop
slot_swl:
    nop
slot_swr:
    nop
slot_sb:
    nop
slot_sh:
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

    li   $v0, 34
    move $a0, $t5
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    lw   $t6, 0($s1)
    li   $v0, 34
    move $a0, $t6
    syscall

    li   $v0, 10
    syscall
