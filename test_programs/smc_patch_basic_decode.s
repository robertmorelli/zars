# Self-modifying code decode probe.
# Patches three NOP slots with machine-code encodings for addi/ori/beq,
# then executes the patched block to validate patched-word decode paths.

.text
.globl main
main:
    # addi $t0, $zero, 42
    li   $t2, 0x2008002A
    la   $t3, slot_addi
    sw   $t2, 0($t3)

    # ori $t1, $t0, 1
    li   $t2, 0x35090001
    la   $t3, slot_ori
    sw   $t2, 0($t3)

    # beq $t1, $t1, +3 (skip fail-print sequence)
    li   $t2, 0x11290003
    la   $t3, slot_beq
    sw   $t2, 0($t3)

    j    slot_addi

slot_addi:
    nop
slot_ori:
    nop
slot_beq:
    nop

    li   $v0, 1
    li   $a0, 999
    syscall

after_branch:
    li   $v0, 1
    move $a0, $t1
    syscall

    li   $v0, 10
    syscall
