# Self-modifying decode probe for patched COP1 arithmetic/convert/compare instructions.

.data
f_words: .word 0x3F800000, 0x40000000, 0xBF800000

.text
.globl main
main:
    la   $s0, f_words
    lwc1 $f0, 0($s0)      # 1.0
    lwc1 $f1, 4($s0)      # 2.0
    lwc1 $f2, 8($s0)      # -1.0

    # add.s $f6, $f0, $f1
    li   $t8, 0x46010180
    la   $t9, slot_add
    sw   $t8, 0($t9)

    # sub.s $f7, $f1, $f0
    li   $t8, 0x460009C1
    la   $t9, slot_sub
    sw   $t8, 0($t9)

    # mul.s $f8, $f0, $f1
    li   $t8, 0x46010202
    la   $t9, slot_mul
    sw   $t8, 0($t9)

    # div.s $f9, $f1, $f0
    li   $t8, 0x46000A43
    la   $t9, slot_div
    sw   $t8, 0($t9)

    # abs.s $f10, $f2
    li   $t8, 0x46001285
    la   $t9, slot_abs
    sw   $t8, 0($t9)

    # neg.s $f11, $f0
    li   $t8, 0x460002C7
    la   $t9, slot_neg
    sw   $t8, 0($t9)

    # cvt.w.s $f13, $f1
    li   $t8, 0x46000B64
    la   $t9, slot_cvtw
    sw   $t8, 0($t9)

    # round.w.s $f14, $f0
    li   $t8, 0x4600038C
    la   $t9, slot_roundw
    sw   $t8, 0($t9)

    # floor.w.s $f15, $f1
    li   $t8, 0x46000BCF
    la   $t9, slot_floorw
    sw   $t8, 0($t9)

    # c.eq.s $f6, $f6
    li   $t8, 0x46063032
    la   $t9, slot_ceq
    sw   $t8, 0($t9)

    # bc1t +3 (skip fail print)
    li   $t8, 0x45010003
    la   $t9, slot_bc1t
    sw   $t8, 0($t9)

    # c.lt.s $f6, $f0  (false)
    li   $t8, 0x4600303C
    la   $t9, slot_clt
    sw   $t8, 0($t9)

    # bc1f +3 (skip fail print)
    li   $t8, 0x45000003
    la   $t9, slot_bc1f
    sw   $t8, 0($t9)

    # mfc1 transfer probes for computed results.
    li   $t8, 0x44083000
    la   $t9, slot_mfc1_t0
    sw   $t8, 0($t9)

    li   $t8, 0x44093800
    la   $t9, slot_mfc1_t1
    sw   $t8, 0($t9)

    li   $t8, 0x440A4000
    la   $t9, slot_mfc1_t2
    sw   $t8, 0($t9)

    li   $t8, 0x440B4800
    la   $t9, slot_mfc1_t3
    sw   $t8, 0($t9)

    li   $t8, 0x440C6800
    la   $t9, slot_mfc1_t4
    sw   $t8, 0($t9)

    li   $t8, 0x440D7000
    la   $t9, slot_mfc1_t5
    sw   $t8, 0($t9)

    li   $t8, 0x440E7800
    la   $t9, slot_mfc1_t6
    sw   $t8, 0($t9)

    li   $t8, 0x440F5000
    la   $t9, slot_mfc1_t7
    sw   $t8, 0($t9)

    li   $t8, 0x44125800
    la   $t9, slot_mfc1_s2
    sw   $t8, 0($t9)

    j    slot_add

slot_add:
    nop
slot_sub:
    nop
slot_mul:
    nop
slot_div:
    nop
slot_abs:
    nop
slot_neg:
    nop
slot_cvtw:
    nop
slot_roundw:
    nop
slot_floorw:
    nop
slot_ceq:
    nop
slot_bc1t:
    nop
    li   $v0, 1
    li   $a0, 111
    syscall

after_bc1t:
slot_clt:
    nop
slot_bc1f:
    nop
    li   $v0, 1
    li   $a0, 222
    syscall

after_bc1f:
slot_mfc1_t0:
    nop
slot_mfc1_t1:
    nop
slot_mfc1_t2:
    nop
slot_mfc1_t3:
    nop
slot_mfc1_t4:
    nop
slot_mfc1_t5:
    nop
slot_mfc1_t6:
    nop
slot_mfc1_t7:
    nop
slot_mfc1_s2:
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

    li   $v0, 34
    move $a0, $t7
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 34
    move $a0, $s2
    syscall

    li   $v0, 10
    syscall
