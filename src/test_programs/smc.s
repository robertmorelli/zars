
# Robert Morelli
# "unhinged fizzbuzz"
# works up to varaible N
# no branches (no b instructions only j instructions)
# no instructions that read flags
# no using fault handlers to move ip
# no adding or multipling pointers
# no jump table
# no indexed memory reads or writes
# no call instruction
# no stack use
# You will have to enable self-modifying code
#
# this was developed with this extension:
# https://marketplace.visualstudio.com/items?itemName=robertmorelli.mips-assembly
# its just running MARS headlessly and it does have a recent patch
#  for non-zero code fields decoding correctly
# this has been added to the MARS repo but might not be present in
#  versions you may download

.text
.globl main
main:
	li			$v0,	5				# Load syscall code for read_int
	syscall								# Execute syscall
	subiu		$t3,	$v0,	1		# Move the input integer from $v0 to $t0
	move		$t6,	$v0				# $t6 used to invert counter
	lw			$t1,	c_mask			# j imm mask
	lw			$t2,	j_op			# used later for masking
	or			$t3,	$t3,	$t2		# add the j opcode to the counter
	nop									# padding for loop
	nop									# padding for loop
loop:									# aligned with page + C for syscall secondary opcode
	la			$t0,	loop 			# t0 to mask into instruction
	srl			$t0,	$t0,	2		# move address to align
	and			$t0,	$t0,	$t1		# make $t0 have the right imm in the right place

	# print newline
	li			$v0,	11
	li			$a0,	10
	syscall

body:									# we need a label here to overwrite in th 15-cycle
	j one								# execute current "subroutine" of 15-cycle
after_body:								# call is banned for being too powerfull this is ra

	subiu		$t3,	$t3,	1		# decrement counter
	
	# insert counter into instruction
	and			$t2,	$t2,	$t3
	or			$t4,	$t2,	$t0

	# store modified instruction
	la			$t5,	j_or_syscall
	sw			$t4,	0($t5)

	# syscall or jump
	li			$v0,	10
j_or_syscall:
	nop

	# 15-cycle subroutines
one:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	two
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	# "return"
	j			after_body

two:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	three
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

three:
	# print fizz
    la			$a0,	fizz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	four
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

four:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	five
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

five:
	# print buzz
    la			$a0,	buzz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	six
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

six:
	# print fizz
    la			$a0,	fizz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	seven
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

seven:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	eight
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

eight:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	nine
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

nine:
	# print fizz
    la			$a0,	fizz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	ten
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

ten:
	# print buzz
    la			$a0,	buzz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	eleven
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

eleven:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	twelve
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

twelve:
	# print fizz
    la			$a0,	fizz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	thirteen
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

thirteen:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	fourteen
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

fourteen:
	# print number
	li			$v0,	1
	xor			$a0,	$t3,	$t2
	subu		$a0,	$t6,	$a0
	syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	fifteen
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

fifteen:
	# print fizzbuzz
    la			$a0,	fizzbuzz
    li			$v0,	4
    syscall

	# store next label in 15 cycle into jump instruction at label "body"
	la			$a0,	one
	srl			$a0,	$a0,	2
	lw			$t8,	j_op
	or			$a0,	$t8,	$a0
	la			$t8,	body
	sw			$a0,	0($t8)

	j			after_body

	# this needs to be at the bottom so the loop label is aligned at page + C
.data
	j_op:		.word	0x08000000	# j 0
	c_mask:		.word	0x03FFFFFF	# mask immediate field of j
	fizz:		.asciiz	"fizz"
	buzz:		.asciiz	"buzz"
	fizzbuzz:	.asciiz	"fizzbuzz"
