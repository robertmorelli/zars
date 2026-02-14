# Self-modifying decode probe for patched movn/movz, trap families, and CP0 transfer/eret.

.text
.globl main
main:
    li   $s0, 7
    li   $s1, 9
    li   $s2, 0
    li   $s3, 1
    li   $s5, 2

    # movz $t0, $s1, $s2
    li   $t8, 0x0232400A
    la   $t9, slot_movz
    sw   $t8, 0($t9)

    # movn $t1, $s1, $s3
    li   $t8, 0x0233480B
    la   $t9, slot_movn
    sw   $t8, 0($t9)

    # tge  $s0, $s1        (false, no trap)
    li   $t8, 0x02110030
    la   $t9, slot_tge
    sw   $t8, 0($t9)

    # tgeu $s0, $s1        (false, no trap)
    li   $t8, 0x02110031
    la   $t9, slot_tgeu
    sw   $t8, 0($t9)

    # tlt  $s1, $s0        (false, no trap)
    li   $t8, 0x02300032
    la   $t9, slot_tlt
    sw   $t8, 0($t9)

    # tltu $s1, $s0        (false, no trap)
    li   $t8, 0x02300033
    la   $t9, slot_tltu
    sw   $t8, 0($t9)

    # teq  $s0, $s1        (false, no trap)
    li   $t8, 0x02110034
    la   $t9, slot_teq
    sw   $t8, 0($t9)

    # tne  $s0, $s0        (false, no trap)
    li   $t8, 0x02100036
    la   $t9, slot_tne
    sw   $t8, 0($t9)

    # tgei  $s0, 9         (false, no trap)
    li   $t8, 0x06080009
    la   $t9, slot_tgei
    sw   $t8, 0($t9)

    # tgeiu $s0, 9         (false, no trap)
    li   $t8, 0x06090009
    la   $t9, slot_tgeiu
    sw   $t8, 0($t9)

    # tlti  $s1, 7         (false, no trap)
    li   $t8, 0x062A0007
    la   $t9, slot_tlti
    sw   $t8, 0($t9)

    # tltiu $s1, 7         (false, no trap)
    li   $t8, 0x062B0007
    la   $t9, slot_tltiu
    sw   $t8, 0($t9)

    # teqi  $s0, 8         (false, no trap)
    li   $t8, 0x060C0008
    la   $t9, slot_teqi
    sw   $t8, 0($t9)

    # tnei  $s0, 7         (false, no trap)
    li   $t8, 0x060E0007
    la   $t9, slot_tnei
    sw   $t8, 0($t9)

    # mtc0 $s5, $12        (set status EXL bit)
    li   $t8, 0x40956000
    la   $t9, slot_set_status
    sw   $t8, 0($t9)

    # mfc0 $t2, $12        (capture status before eret)
    li   $t8, 0x400A6000
    la   $t9, slot_get_status_before
    sw   $t8, 0($t9)

    # mtc0 $s4, $14        (set EPC)
    li   $t8, 0x40947000
    la   $t9, slot_set_epc
    sw   $t8, 0($t9)

    # mfc0 $t3, $12        (capture status after eret)
    li   $t8, 0x400B6000
    la   $t9, slot_get_status_after
    sw   $t8, 0($t9)

    # eret
    li   $t8, 0x42000018
    la   $t9, slot_eret
    sw   $t8, 0($t9)

    la   $s4, after_eret
    j    slot_movz

slot_movz:
    nop
slot_movn:
    nop
slot_tge:
    nop
slot_tgeu:
    nop
slot_tlt:
    nop
slot_tltu:
    nop
slot_teq:
    nop
slot_tne:
    nop
slot_tgei:
    nop
slot_tgeiu:
    nop
slot_tlti:
    nop
slot_tltiu:
    nop
slot_teqi:
    nop
slot_tnei:
    nop
slot_set_status:
    nop
slot_get_status_before:
    nop
slot_set_epc:
    nop
slot_eret:
    nop

    li   $v0, 1
    li   $a0, 999
    syscall

after_eret:
slot_get_status_after:
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
