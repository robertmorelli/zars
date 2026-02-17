.text
.globl main
main:
    # Test different subiu forms
    subiu $t0, $t1, 1          # small immediate
    subiu $t2, $t3, 100        # 16-bit immediate
    subiu $t4, $t5, 100000     # 32-bit immediate
    li $v0, 10
    syscall
