# Dialog syscall headless-mode parity probe.
# In this environment MARS throws HeadlessException and emits a fixed
# termination message to stdout.

.data
msg:  .asciiz "dialog"
msg2: .asciiz "suffix"
buf:  .space 32

.text
main:
    la $a0, msg
    la $a1, msg2
    li $a2, 8
    li $a3, 0
    li $v0, 54
    syscall

    # Unreachable when headless termination behavior is matched.
    li $v0, 1
    li $a0, 9
    syscall
