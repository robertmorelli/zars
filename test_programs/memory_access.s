# Load/store behavior, sign extension, and data directives.

.data
values_b:    .byte -1, 0x7f
values_h:    .half -2, 0x1234
values_w:    .word 0x01020304, -3
scratch:     .space 8

.text
.globl main

main:
    la   $s0, values_b
    lb   $t0, 0($s0)        # -1
    lbu  $t1, 0($s0)        # 255

    la   $s1, values_h
    lh   $t2, 0($s1)        # -2
    lhu  $t3, 2($s1)        # 4660

    la   $s2, values_w
    lw   $t4, 0($s2)        # 16909060
    lw   $t5, 4($s2)        # -3

    la   $s3, scratch
    sw   $t4, 0($s3)
    sh   $t3, 4($s3)
    sb   $t1, 6($s3)

    lw   $t6, 0($s3)
    lhu  $t7, 4($s3)
    lbu  $t8, 6($s3)

    jal  print_int_line_t0
    jal  print_int_line_t1
    jal  print_int_line_t2
    jal  print_int_line_t3
    jal  print_int_line_t4
    jal  print_int_line_t5
    jal  print_int_line_t6
    jal  print_int_line_t7
    jal  print_int_line_t8

    li   $v0, 10
    syscall

print_int_line_t0:
    move $a0, $t0
    j    print_int_line

print_int_line_t1:
    move $a0, $t1
    j    print_int_line

print_int_line_t2:
    move $a0, $t2
    j    print_int_line

print_int_line_t3:
    move $a0, $t3
    j    print_int_line

print_int_line_t4:
    move $a0, $t4
    j    print_int_line

print_int_line_t5:
    move $a0, $t5
    j    print_int_line

print_int_line_t6:
    move $a0, $t6
    j    print_int_line

print_int_line_t7:
    move $a0, $t7
    j    print_int_line

print_int_line_t8:
    move $a0, $t8

print_int_line:
    li   $v0, 1
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
