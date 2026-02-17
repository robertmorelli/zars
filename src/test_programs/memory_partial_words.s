# Partial-word memory instruction coverage.
# Exercises ll/sc and left/right load-store instructions against a single word.

.data
word0: .word 0x11223344

.text
.globl main

main:
    # ll behaves like lw in MARS single-processor simulation.
    la   $s0, word0
    ll   $t0, 0($s0)
    li   $v0, 34
    move $a0, $t0
    syscall
    jal  print_newline

    # sc stores and always reports success by writing 1 into source register.
    li   $t1, 0x55667788
    sc   $t1, 0($s0)
    lw   $t2, 0($s0)
    li   $v0, 34
    move $a0, $t2
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $t1
    syscall
    jal  print_newline

    # Unaligned left/right loads merge bytes with destination register contents.
    li   $t3, 0
    lwl  $t3, 1($s0)
    li   $v0, 34
    move $a0, $t3
    syscall
    jal  print_newline

    li   $t4, 0
    lwr  $t4, 2($s0)
    li   $v0, 34
    move $a0, $t4
    syscall
    jal  print_newline

    # Unaligned left/right stores copy selected source bytes into memory.
    li   $t5, 0xa1b2c3d4
    swl  $t5, 1($s0)
    lw   $t6, 0($s0)
    li   $v0, 34
    move $a0, $t6
    syscall
    jal  print_newline

    li   $t7, 0xe5f60718
    swr  $t7, 2($s0)
    lw   $t8, 0($s0)
    li   $v0, 34
    move $a0, $t8
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
