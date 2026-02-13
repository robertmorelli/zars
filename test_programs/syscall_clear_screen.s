# MARS extension syscall 60 (ClearScreen).
# In command mode this should be a no-op and not crash.

.data
msg: .asciiz "clear-screen-ok"

.text
.globl main

main:
    li   $v0, 60
    syscall

    li   $v0, 4
    la   $a0, msg
    syscall

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
