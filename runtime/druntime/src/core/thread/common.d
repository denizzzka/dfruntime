module core.thread.common;

import core.thread.osthread;
import core.thread.threadbase;

package Thread toThread(return scope ThreadBase t) @trusted nothrow @nogc pure
{
    return cast(Thread) cast(void*) t;
}

private extern(D) static void thread_yield() @nogc nothrow
{
    Thread.yield();
}

/**
 * Registers the calling thread for use with the D Runtime.  If this routine
 * is called for a thread which is already registered, no action is performed.
 *
 * NOTE: This routine does not run thread-local static constructors when called.
 *       If full functionality as a D thread is desired, the following function
 *       must be called after thread_attachThis:
 *
 *       extern (C) void rt_moduleTlsCtor();
 *
 * See_Also:
 *     $(REF thread_detachThis, core,thread,threadbase)
 */
extern(C) Thread thread_attachThis()
{
    return thread_attachThis_tpl!Thread();
}

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

version (D_InlineAsm_X86)
{
    version (Windows)
        version = AsmX86_Windows;
    else version (Posix)
        version = AsmX86_Posix;
}
else version (D_InlineAsm_X86_64)
{
    version (Windows)
    {
        version = AsmX86_64_Windows;
    }
    else version (Posix)
    {
        version = AsmX86_64_Posix;
    }
}

version (LDC) {} else
version (PPC64) version = ExternStackShell;

// Calls the given delegate, passing the current thread's stack pointer to it.
package extern(D) void callWithStackShell(scope callWithStackShellDg fn) nothrow
in (fn)
{
    // The purpose of the 'shell' is to ensure all the registers get
    // put on the stack so they'll be scanned. We only need to push
    // the callee-save registers.
    void *sp = void;
    version (GNU)
    {
        __builtin_unwind_init();
        sp = &sp;
    }
    else version (AsmX86_Posix)
    {
        size_t[3] regs = void;
        asm pure nothrow @nogc
        {
            mov [regs + 0 * 4], EBX;
            mov [regs + 1 * 4], ESI;
            mov [regs + 2 * 4], EDI;

            mov sp[EBP], ESP;
        }
    }
    else version (AsmX86_Windows)
    {
        size_t[3] regs = void;
        asm pure nothrow @nogc
        {
            mov [regs + 0 * 4], EBX;
            mov [regs + 1 * 4], ESI;
            mov [regs + 2 * 4], EDI;

            mov sp[EBP], ESP;
        }
    }
    else version (AsmX86_64_Posix)
    {
        size_t[5] regs = void;
        asm pure nothrow @nogc
        {
            mov [regs + 0 * 8], RBX;
            mov [regs + 1 * 8], R12;
            mov [regs + 2 * 8], R13;
            mov [regs + 3 * 8], R14;
            mov [regs + 4 * 8], R15;

            mov sp[RBP], RSP;
        }
    }
    else version (AsmX86_64_Windows)
    {
        size_t[7] regs = void;
        asm pure nothrow @nogc
        {
            mov [regs + 0 * 8], RBX;
            mov [regs + 1 * 8], RSI;
            mov [regs + 2 * 8], RDI;
            mov [regs + 3 * 8], R12;
            mov [regs + 4 * 8], R13;
            mov [regs + 5 * 8], R14;
            mov [regs + 6 * 8], R15;

            mov sp[RBP], RSP;
        }
    }
    else version (LDC)
    {
        version (PPC_Any)
        {
            // Nonvolatile registers, according to:
            // System V Application Binary Interface
            // PowerPC Processor Supplement, September 1995
            // ELFv1: 64-bit PowerPC ELF ABI Supplement 1.9, July 2004
            // ELFv2: Power Architecture, 64-Bit ELV V2 ABI Specification,
            //        OpenPOWER ABI for Linux Supplement, July 2014
            size_t[18] regs = void;
            static foreach (i; 0 .. regs.length)
            {{
                enum int j = 14 + i; // source register
                static if (j == 21)
                {
                    // Work around LLVM bug 21443 (http://llvm.org/bugs/show_bug.cgi?id=21443)
                    // Because we clobber r0 a different register is chosen
                    asm pure nothrow @nogc { ("std "~j.stringof~", %0") : "=m" (regs[i]) : : "r0"; }
                }
                else
                    asm pure nothrow @nogc { ("std "~j.stringof~", %0") : "=m" (regs[i]); }
            }}

            asm pure nothrow @nogc { "std 1, %0" : "=m" (sp); }
        }
        else version (AArch64)
        {
            // Callee-save registers, x19-x28 according to AAPCS64, section
            // 5.1.1.  Include x29 fp because it optionally can be a callee
            // saved reg
            size_t[11] regs = void;
            // store the registers in pairs
            asm pure nothrow @nogc
            {
                "stp x19, x20, %0" : "=m" (regs[ 0]), "=m" (regs[1]);
                "stp x21, x22, %0" : "=m" (regs[ 2]), "=m" (regs[3]);
                "stp x23, x24, %0" : "=m" (regs[ 4]), "=m" (regs[5]);
                "stp x25, x26, %0" : "=m" (regs[ 6]), "=m" (regs[7]);
                "stp x27, x28, %0" : "=m" (regs[ 8]), "=m" (regs[9]);
                "str x29, %0"      : "=m" (regs[10]);
                "mov %0, sp"       : "=r" (sp);
            }
        }
        else version (ARM)
        {
            // Callee-save registers, according to AAPCS, section 5.1.1.
            // arm and thumb2 instructions
            size_t[8] regs = void;
            asm pure nothrow @nogc
            {
                "stm %0, {r4-r11}" : : "r" (regs.ptr) : "memory";
                "mov %0, sp"       : "=r" (sp);
            }
        }
        else version (MIPS_N64)
        {
            size_t[10] regs = void;
            static foreach (i; 0 .. 8)
            {{
                asm pure nothrow @nogc { ("sd $s"~i.stringof~", %0") : "=m" (regs[i]); }
            }}
            asm pure nothrow @nogc {
                ("sd $gp, %0") : "=m" (regs[8]);
                ("sd $fp, %0") : "=m" (regs[9]); 
                ("sd $ra, %0") : "=m" (sp);
            }
        }
        else version (MIPS_Any)
        {
            version (MIPS32)      enum store = "sw";
            else version (MIPS64) enum store = "sd";
            else static assert(0);

            // Callee-save registers, according to MIPS Calling Convention
            // and MIPSpro N32 ABI Handbook, chapter 2, table 2-1.
            // FIXME: Should $28 (gp) and $30 (s8) be saved, too?
            size_t[8] regs = void;
            asm pure nothrow @nogc { ".set noat"; }
            static foreach (i; 0 .. regs.length)
            {{
                enum int j = 16 + i; // source register
                asm pure nothrow @nogc { (store ~ " $"~j.stringof~", %0") : "=m" (regs[i]); }
            }}
            asm pure nothrow @nogc { (store ~ " $29, %0") : "=m" (sp); }
            asm pure nothrow @nogc { ".set at"; }
        }
        else version (RISCV_Any)
        {
            version (RISCV32)      enum store = "sw";
            else version (RISCV64) enum store = "sd";
            else static assert(0);

            version (D_HardFloat)  enum regs_len = 24;
            else                   enum regs_len = 12;

            // Callee-save registers, according to RISCV Calling Convention
            // https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-cc.adoc
            size_t[regs_len] regs = void;
            static foreach (i; 0 .. 12)
            {{
                enum int j = i;
                asm pure nothrow @nogc { (store ~ " s"~j.stringof~", %0") : "=m" (regs[i]); }
            }}

            version (D_HardFloat)
            static foreach (i; 0 .. 12)
            {{
                enum int j = i;
                asm pure nothrow @nogc { ("f" ~ store ~ " fs"~j.stringof~", %0") : "=m" (regs[i + 12]); }
            }}
            asm pure nothrow @nogc { (store ~ " sp, %0") : "=m" (sp); }
        }
        else version (LoongArch64)
        {
            // Callee-save registers, according to LoongArch Calling Convention
            // https://loongson.github.io/LoongArch-Documentation/LoongArch-ELF-ABI-EN.html
            size_t[18] regs = void;
            static foreach (i; 0 .. 8)
            {{
                enum int j = i;
                // save $fs0 - $fs7
                asm pure nothrow @nogc { ( "fst.d $fs"~j.stringof~", %0") : "=m" (regs[i]); }
            }}
            static foreach (i; 0 .. 9)
            {{
                enum int j = i;
                // save $s0 - $s8
                asm pure nothrow @nogc { ( "st.d $s"~j.stringof~", %0") : "=m" (regs[i + 8]); }
            }}
            // save $fp (or $s9) and $sp
            asm pure nothrow @nogc { ( "st.d $fp, %0") : "=m" (regs[17]); }
            asm pure nothrow @nogc { ( "st.d $sp, %0") : "=m" (sp); }
        }
        else
        {
            static assert(false, "Architecture not supported.");
        }
    }
    else
    {
        static assert(false, "Architecture not supported.");
    }

    fn(sp);
}
