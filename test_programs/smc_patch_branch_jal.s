# Self-modifying decode probe for patched beq/bne/jal/jr behavior.

.text
.globl main
main:
    li   $t0, 1
    li   $t1, 2

    # beq $t0, $t0, +3 (skip 999 print block)
    li   $t2, 0x11080003
    la   $t3, slot_beq
    sw   $t2, 0($t3)

    # bne $t0, $t1, +3 (skip 888 print block)
    li   $t2, 0x15090003
    la   $t3, slot_bne
    sw   $t2, 0($t3)

    # jr $ra (used by callee)
    li   $t2, 0x03e00008
    la   $t3, slot_jr
    sw   $t2, 0($t3)

    # jal callee (opcode bits + target field)
    la   $t2, callee
    srl  $t2, $t2, 2
    li   $t3, 0x0c000000
    or   $t2, $t2, $t3
    la   $t3, slot_jal
    sw   $t2, 0($t3)

    li   $s0, 0
    j    slot_beq

slot_beq:
    nop
    li   $v0, 1
    li   $a0, 999
    syscall

slot_bne:
    nop
    li   $v0, 1
    li   $a0, 888
    syscall

slot_jal:
    nop

after_call:
    li   $v0, 1
    move $a0, $s0
    syscall

    li   $v0, 10
    syscall

callee:
    li   $s0, 123
slot_jr:
    nop
