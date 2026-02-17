# File I/O syscalls: open(13), write(15), close(16), read(14).

.data
file_name:    .asciiz "mars_io_test.txt"
write_buf:    .asciiz "alpha\nbeta\n"
read_buf:     .space 64

.text
.globl main

main:
    # fd = open(file_name, write_create, ignored_mode)
    li   $v0, 13
    la   $a0, file_name
    li   $a1, 1
    li   $a2, 0
    syscall
    move $s0, $v0

    # write(fd, write_buf, 11)
    li   $v0, 15
    move $a0, $s0
    la   $a1, write_buf
    li   $a2, 11
    syscall

    # close(fd)
    li   $v0, 16
    move $a0, $s0
    syscall

    # fd = open(file_name, read_only, ignored_mode)
    li   $v0, 13
    la   $a0, file_name
    li   $a1, 0
    li   $a2, 0
    syscall
    move $s1, $v0

    # count = read(fd, read_buf, 63)
    li   $v0, 14
    move $a0, $s1
    la   $a1, read_buf
    li   $a2, 63
    syscall
    move $t0, $v0

    # close(fd)
    li   $v0, 16
    move $a0, $s1
    syscall

    # Null-terminate read_buf[count]
    la   $t1, read_buf
    addu $t2, $t1, $t0
    sb   $zero, 0($t2)

    # Print the read buffer as a string.
    li   $v0, 4
    la   $a0, read_buf
    syscall

    li   $v0, 10
    syscall
