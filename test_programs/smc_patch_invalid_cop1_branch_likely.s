# Unsupported COP1 branch-likely encoding through patched text word.
.text
main:
    li   $t8, 0x45020000
    la   $t9, slot_bad
    sw   $t8, 0($t9)
    j    slot_bad
slot_bad:
    nop
