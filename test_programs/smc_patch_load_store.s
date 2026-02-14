# Self-modifying decode probe for patched addi/andi/lw/sw and jr.

.data
storage: .word 0

.text
.globl main
main:
    la   $s0, storage

    # addi $t0, $zero, 77
    li   $t2, 0x2008004d
    la   $t3, slot_addi
    sw   $t2, 0($t3)

    # sw $t0, 0($s0)
    li   $t2, 0xae080000
    la   $t3, slot_sw
    sw   $t2, 0($t3)

    # lw $t1, 0($s0)
    li   $t2, 0x8e090000
    la   $t3, slot_lw
    sw   $t2, 0($t3)

    # andi $t3, $t1, 0x00ff
    li   $t2, 0x312b00ff
    la   $t3, slot_andi
    sw   $t2, 0($t3)

    # jr $ra
    li   $t2, 0x03e00008
    la   $t3, slot_jr
    sw   $t2, 0($t3)

    la   $ra, after_slots
    j    slot_addi

slot_addi:
    nop
slot_sw:
    nop
slot_lw:
    nop
slot_andi:
    nop
slot_jr:
    nop

after_slots:
    li   $v0, 1
    move $a0, $t1
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall

    li   $v0, 1
    move $a0, $t3
    syscall

    li   $v0, 10
    syscall
