# Self-modifying decode probe for patched regimm branch family and blez/bgtz.

.text
.globl main
main:
    li   $s0, -1
    li   $s1, 1
    li   $s2, 0

    # bltz   $s0, +1
    li   $t8, 0x06000001
    la   $t9, slot_bltz
    sw   $t8, 0($t9)

    # bgez   $s1, +1
    li   $t8, 0x06210001
    la   $t9, slot_bgez
    sw   $t8, 0($t9)

    # blez   $s0, +1
    li   $t8, 0x1A000001
    la   $t9, slot_blez
    sw   $t8, 0($t9)

    # bgtz   $s1, +1
    li   $t8, 0x1E200001
    la   $t9, slot_bgtz
    sw   $t8, 0($t9)

    # bltzal $s0, +1
    li   $t8, 0x06100001
    la   $t9, slot_bltzal
    sw   $t8, 0($t9)

    # bgezal $s1, +1
    li   $t8, 0x06310001
    la   $t9, slot_bgezal
    sw   $t8, 0($t9)

    j    slot_bltz

slot_bltz:
    nop
    addiu $s2, $s2, 100
after_bltz:
    addiu $s2, $s2, 1

slot_bgez:
    nop
    addiu $s2, $s2, 100
after_bgez:
    addiu $s2, $s2, 1

slot_blez:
    nop
    addiu $s2, $s2, 100
after_blez:
    addiu $s2, $s2, 1

slot_bgtz:
    nop
    addiu $s2, $s2, 100
after_bgtz:
    addiu $s2, $s2, 1

slot_bltzal:
    nop
    addiu $s2, $s2, 100
after_bltzal:
    addiu $s2, $s2, 1

slot_bgezal:
    nop
    addiu $s2, $s2, 100
after_bgezal:
    addiu $s2, $s2, 1

    li   $v0, 1
    move $a0, $s2
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $ra
    syscall

    li   $v0, 10
    syscall
