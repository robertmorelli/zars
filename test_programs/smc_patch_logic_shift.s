# Self-modifying code decode probe for R-type logic/shift instructions.
# Patches a linear block of NOPs with machine words and jumps into that block.

.text
.globl main
main:
    # ori $t0, $zero, 0x00ff
    li   $t2, 0x340800ff
    la   $t3, slot_ori
    sw   $t2, 0($t3)

    # sll $t1, $t0, 4
    li   $t2, 0x00084900
    la   $t3, slot_sll
    sw   $t2, 0($t3)

    # sra $t2, $t1, 2
    li   $t2, 0x00095083
    la   $t3, slot_sra
    sw   $t2, 0($t3)

    # and $t3, $t1, $t2
    li   $t2, 0x012a5824
    la   $t3, slot_and
    sw   $t2, 0($t3)

    # xor $t4, $t1, $t2
    li   $t2, 0x012a6026
    la   $t3, slot_xor
    sw   $t2, 0($t3)

    # nor $t5, $t1, $t2
    li   $t2, 0x012a6827
    la   $t3, slot_nor
    sw   $t2, 0($t3)

    # jr $ra
    li   $t2, 0x03e00008
    la   $t3, slot_jr
    sw   $t2, 0($t3)

    # Return after the patched block finishes.
    la   $ra, after_slots
    j    slot_ori

slot_ori:
    nop
slot_sll:
    nop
slot_sra:
    nop
slot_and:
    nop
slot_xor:
    nop
slot_nor:
    nop
slot_jr:
    nop

after_slots:
    li   $v0, 34
    move $a0, $t3
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall

    li   $v0, 34
    move $a0, $t4
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall

    li   $v0, 34
    move $a0, $t5
    syscall

    li   $v0, 10
    syscall
