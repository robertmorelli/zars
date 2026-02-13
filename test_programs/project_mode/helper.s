# Helper file for project_main.s

.text
.globl helper_double

helper_double:
    addu $v0, $a0, $a0
    jr   $ra
