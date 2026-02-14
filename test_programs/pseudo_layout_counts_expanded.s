# Expanded pseudo-op layout probe.
# This fixture locks in byte-length parity for pseudo families that depend on
# immediate width and unaligned/pair-memory addressing forms.

.data
data_label: .word 0

.text
main:
    la   $t0, addi_32_after
    la   $t1, addi_32_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, andi_3op_32_after
    la   $t1, andi_3op_32_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, andi_2op_32_after
    la   $t1, andi_2op_32_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, beq_imm16_after
    la   $t1, beq_imm16_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, beq_imm32_after
    la   $t1, beq_imm32_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, mulo_rr_after
    la   $t1, mulo_rr_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, div_rr_after
    la   $t1, div_rr_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, ulw_base_after
    la   $t1, ulw_base_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, ulh_base_after
    la   $t1, ulh_base_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, ush_base_after
    la   $t1, ush_base_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, ld_base_after
    la   $t1, ld_base_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, sd_label_base_after
    la   $t1, sd_label_base_before
    subu $a0, $t0, $t1
    li   $v0, 1
    syscall

    li   $v0, 10
    syscall

addi_32_before:
    addi $s0, $s1, 100000
addi_32_after:

andi_3op_32_before:
    andi $s0, $s1, 100000
andi_3op_32_after:

andi_2op_32_before:
    andi $s0, 100000
andi_2op_32_after:

beq_imm16_before:
    beq  $s0, -100, beq_imm16_target
beq_imm16_target:
beq_imm16_after:

beq_imm32_before:
    beq  $s0, 100000, beq_imm32_target
beq_imm32_target:
beq_imm32_after:

mulo_rr_before:
    mulo $s0, $s1, $s2
mulo_rr_after:

div_rr_before:
    div  $s0, $s1, $s2
div_rr_after:

ulw_base_before:
    ulw  $s0, ($s1)
ulw_base_after:

ulh_base_before:
    ulh  $s0, ($s1)
ulh_base_after:

ush_base_before:
    ush  $s0, ($s1)
ush_base_after:

ld_base_before:
    ld   $s0, ($s1)
ld_base_after:

sd_label_base_before:
    sd   $s0, data_label($s1)
sd_label_base_after:
