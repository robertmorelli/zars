# Invalid COP1 fmt.w funct selector through patched text word.
.text
main:
    li   $t8, 0x46800000
    la   $t9, slot_bad
    sw   $t8, 0($t9)
    j    slot_bad
slot_bad:
    nop
