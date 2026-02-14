# Self-modifying decode probe for patched COP1 transfers, lwc1/swc1, and bc1t/bc1f.

.data
src_word: .word 0x3F800000
dst_word: .word 0

.text
.globl main
main:
    la   $s0, src_word
    la   $s1, dst_word
    li   $t5, 0x40000000

    # lwc1 $f4, 0($s0)
    li   $t8, 0xC6040000
    la   $t9, slot_lwc1
    sw   $t8, 0($t9)

    # mfc1 $t4, $f4
    li   $t8, 0x440C2000
    la   $t9, slot_mfc1_f4
    sw   $t8, 0($t9)

    # mtc1 $t5, $f5
    li   $t8, 0x448D2800
    la   $t9, slot_mtc1_f5
    sw   $t8, 0($t9)

    # mfc1 $t6, $f5
    li   $t8, 0x440E2800
    la   $t9, slot_mfc1_f5
    sw   $t8, 0($t9)

    # swc1 $f4, 0($s1)
    li   $t8, 0xE6240000
    la   $t9, slot_swc1
    sw   $t8, 0($t9)

    # bc1t +3 (skip fail print)
    li   $t8, 0x45010003
    la   $t9, slot_bc1t
    sw   $t8, 0($t9)

    # bc1f +3 (skip fail print)
    li   $t8, 0x45000003
    la   $t9, slot_bc1f
    sw   $t8, 0($t9)

    j    slot_lwc1

slot_lwc1:
    nop
slot_mfc1_f4:
    nop
slot_mtc1_f5:
    nop
slot_mfc1_f5:
    nop
slot_swc1:
    nop

    # Set condition true; patched bc1t should take branch.
    c.eq.s $f4, $f4
slot_bc1t:
    nop
    li   $v0, 1
    li   $a0, 111
    syscall

after_bc1t:
    # Set condition false; patched bc1f should take branch.
    c.lt.s $f4, $f4
slot_bc1f:
    nop
    li   $v0, 1
    li   $a0, 222
    syscall

after_bc1f:
    lw   $t7, 0($s1)

    li   $v0, 1
    move $a0, $t4
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

    li   $v0, 34
    move $a0, $t7
    syscall

    li   $v0, 10
    syscall
