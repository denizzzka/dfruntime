/**
 * Support code for RISC-V fibers.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Denis Feklushkin
 */

#if defined(__riscv) && (__riscv_xlen == 32)

/**
 * Parameters:
 * a0 - void** - ptr to old stack pointer
 * a1 - void*  - new stack pointer
 *
 * RISCV32 ABI registers:
 * x0       zero    : hardwired to zero
 * x1       ra      : return address
 * x2       sp      : stack pointer
 * x3       gp      : global pointer (variables are ‘relaxed’ and accessed via a relative imm offset from the gp)
 * x4       tp      : thread pointer
 * x5-x7    t0-t2   : temporary/scratch registers
 * x8       fp      : callee-saved register 0 / frame pointer
 * x9       s1      : callee-saved register 1
 * x10-x17  a0-a7   : function arguments
 * x18-x27  s2-s11  : callee-saved registers
 * x28-x31  t3-t6   : temporary/scratch registers
 */
.text
.globl fiber_switchContext
fiber_switchContext:
    // Reserve space on the stack to store registers
    addi sp, sp, -(13 * 4) // num registers to store * 4 byte register size

    // Store registers data on the stack
    sw ra, (0 * 4)(sp)
    sw s0, (1 * 4)(sp)
    sw s1, (2 * 4)(sp)
    sw s2, (3 * 4)(sp)
    sw s3, (4 * 4)(sp)
    sw s4, (5 * 4)(sp)
    sw s5, (6 * 4)(sp)
    sw s6, (7 * 4)(sp)
    sw s7, (8 * 4)(sp)
    sw s8, (9 * 4)(sp)
    sw s9, (10 * 4)(sp)
    sw s10, (11 * 4)(sp)
    sw s11, (12 * 4)(sp)

    // Adjusts sp back by one word to avoid GC scan ra in the stack frame
    // TODO: redundant step? Can we reserve less space at first stage and place ra above of it?
    addi sp, sp, 1 * 4;

    // Save current sp to oldp
    sw sp, (a0)

    // Load sp from newp (with keep in mind about sp adjustment)
    addi sp, a1, -1 * 4;

    // Load registers from obtained stack
    lw ra, (0 * 4)(sp)
    lw s0, (1 * 4)(sp)
    lw s1, (2 * 4)(sp)
    lw s2, (3 * 4)(sp)
    lw s3, (4 * 4)(sp)
    lw s4, (5 * 4)(sp)
    lw s5, (6 * 4)(sp)
    lw s6, (7 * 4)(sp)
    lw s7, (8 * 4)(sp)
    lw s8, (9 * 4)(sp)
    lw s9, (10 * 4)(sp)
    lw s10, (11 * 4)(sp)
    lw s11, (12 * 4)(sp)

    // Freeing stack
    addi sp, sp, (13 * 4)

    // Return
    jr ra

#endif
