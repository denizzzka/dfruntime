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
 * x8       s0/fp   : callee-saved register 0 AKA frame pointer
 * x9       s1      : callee-saved register 1
 * x10-x17  a0-a7   : function arguments
 * x18-x27  s2-s11  : callee-saved registers
 * x28-x31  t3-t6   : temporary/scratch registers
 */
.text
.globl fiber_switchContext
.type  fiber_switchContext, @function
fiber_switchContext:
    // TODO: replace numbers and load/store instruction names by macroses

    // Reserve space on the stack to store registers
    addi sp, sp, -(12 * 4) // num registers to store * 4 byte register size

    // Store ra above of the stack border to avoid GC scan of ra in the stack frame
    sw ra, -4(sp)

    // Store registers data on the stack
    sw s0, (0 * 4)(sp)
    sw s1, (1 * 4)(sp)
    sw s2, (2 * 4)(sp)
    sw s3, (3 * 4)(sp)
    sw s4, (4 * 4)(sp)
    sw s5, (5 * 4)(sp)
    sw s6, (6 * 4)(sp)
    sw s7, (7 * 4)(sp)
    sw s8, (8 * 4)(sp)
    sw s9, (9 * 4)(sp)
    sw s10, (10 * 4)(sp)
    sw s11, (11 * 4)(sp)

    // Save current sp to oldp
    sw sp, (a0)

    // Load sp from newp (with keep in mind about sp adjustment)
    addi sp, a1, 0;

    // Load ra from above of the stack border
    lw ra, -4(sp)

    // Load registers from obtained stack
    lw s0, (0 * 4)(sp)
    lw s1, (1 * 4)(sp)
    lw s2, (2 * 4)(sp)
    lw s3, (3 * 4)(sp)
    lw s4, (4 * 4)(sp)
    lw s5, (5 * 4)(sp)
    lw s6, (6 * 4)(sp)
    lw s7, (7 * 4)(sp)
    lw s8, (8 * 4)(sp)
    lw s9, (9 * 4)(sp)
    lw s10, (10 * 4)(sp)
    lw s11, (11 * 4)(sp)

    // Freeing stack
    addi sp, sp, (12 * 4)

    // Return
    jr ra

#endif
