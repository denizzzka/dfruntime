/**
 * The fiber module provides OS-indepedent lightweight threads aka fibers.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak
 * Source:    $(DRUNTIMESRC core/thread/fiber/package.d)
 */

module core.thread.fiber;

import core.thread.fiber.base: FiberBase, fiber_entryPoint;
import core.thread.threadbase;
import core.thread.threadgroup;
import core.thread.types;
import core.thread.context;
import core.thread.stack: isStackGrowingDown;

import core.memory : pageSize;

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

version (LDC)
{
    import ldc.attributes;
    import ldc.llvmasm;

    // Unconditionally change ABI to support sanitizers (adds fields to data structures):
    version = SupportSanitizers_ABI;
    // But runtime code is conditionally added by `SupportSanitizers`:
    version (SupportSanitizers)
    {
        import ldc.sanitizers_optionally_linked;
    }
}
else
    private enum assumeUsed = null;

///////////////////////////////////////////////////////////////////////////////
// Fiber Platform Detection
///////////////////////////////////////////////////////////////////////////////

package
{
    version (D_InlineAsm_X86)
    {
        version = AsmX86_Posix;
        version = AlignFiberStackTo16Byte;
    }
    else version (D_InlineAsm_X86_64)
    {
        version = AsmX86_64_Posix;
        version = AlignFiberStackTo16Byte;
    }
    else version (PPC)
    {
        version (OSX)
        {
            version = AsmPPC_Darwin;
            version = AsmExternal;
            version = AlignFiberStackTo16Byte;
        }
        else version (Posix)
        {
            version = AsmPPC_Posix;
            version = AsmExternal;
        }
    }
    else version (PPC64)
    {
        version (OSX)
        {
            version = AsmPPC_Darwin;
            version = AsmExternal;
            version = AlignFiberStackTo16Byte;
        }
        else version (Posix)
        {
            version = AsmPPC64_Posix;
            version = AsmExternal;
            version = AlignFiberStackTo16Byte;
        }
    }
    else version (MIPS_O32)
    {
        version (Posix)
        {
            version = AsmMIPS_O32_Posix;
            version = AsmExternal;
        }
    }
    else version (MIPS_N64)
    {
        version (Posix)
        {
            version = AsmMIPS_N64_Posix;
            version = AsmExternal;
        }
    }
    else version (AArch64)
    {
        version (Posix)
        {
            version = AsmAArch64_Posix;
            version = AsmExternal;
            version = AlignFiberStackTo16Byte;
        }
    }
    else version (ARM)
    {
        version (Posix)
        {
            version = AsmARM_Posix;
            version = AsmExternal;
        }
    }
    else version (SPARC)
    {
        // NOTE: The SPARC ABI specifies only doubleword alignment.
        version = AlignFiberStackTo16Byte;
    }
    else version (SPARC64)
    {
        version = AlignFiberStackTo16Byte;
    }
    else version (LoongArch64)
    {
        version (Posix)
        {
            version = AsmLoongArch64_Posix;
            version = AsmExternal;
            version = AlignFiberStackTo16Byte;
        }
    }

    version (Posix)
    {
        version (AsmX86_Posix)      {} else
        version (AsmX86_64_Posix)   {} else
        version (AsmExternal)       {} else
        {
            // NOTE: The ucontext implementation requires architecture specific
            //       data definitions to operate so testing for it must be done
            //       by checking for the existence of ucontext_t rather than by
            //       a version identifier.  Please note that this is considered
            //       an obsolescent feature according to the POSIX spec, so a
            //       custom solution is still preferred.
            import core.sys.posix.ucontext;
        }
    }
}

///////////////////////////////////////////////////////////////////////////////
// Fiber Entry Point and Context Switch
///////////////////////////////////////////////////////////////////////////////

package
{
    import core.atomic : atomicStore, cas, MemoryOrder;
    import core.exception : onOutOfMemoryError;
    import core.stdc.stdlib : abort;

  // Look above the definition of 'class Fiber' for some information about the implementation of this routine
  version (AsmExternal)
  {
      extern (C) void fiber_switchContext( void** oldp, void* newp ) nothrow @nogc;
      version (AArch64)
          extern (C) void fiber_trampoline() nothrow;
      version (LoongArch64)
          extern (C) void fiber_trampoline() nothrow;
  }
  else
    extern (C) void fiber_switchContext( void** oldp, void* newp ) nothrow @nogc
    {
        // NOTE: The data pushed and popped in this routine must match the
        //       default stack created by Fiber.initStack or the initial
        //       switch into a new context will fail.

        version (AsmX86_Posix)
        {
            asm pure nothrow @nogc
            {
                naked;

                // save current stack state
                push EBP;
                mov  EBP, ESP;
                push EDI;
                push ESI;
                push EBX;
                push EAX;

                // store oldp again with more accurate address
                mov EAX, dword ptr 8[EBP];
                mov [EAX], ESP;
                // load newp to begin context switch
                mov ESP, dword ptr 12[EBP];

                // load saved state from new stack
                pop EAX;
                pop EBX;
                pop ESI;
                pop EDI;
                pop EBP;

                // 'return' to complete switch
                pop ECX;
                jmp ECX;
            }
        }
        else version (AsmX86_64_Posix)
        {
            asm pure nothrow @nogc
            {
                naked;

                // save current stack state
                push RBP;
                mov  RBP, RSP;
                push RBX;
                push R12;
                push R13;
                push R14;
                push R15;

                // store oldp
                mov [RDI], RSP;
                // load newp to begin context switch
                mov RSP, RSI;

                // load saved state from new stack
                pop R15;
                pop R14;
                pop R13;
                pop R12;
                pop RBX;
                pop RBP;

                // 'return' to complete switch
                pop RCX;
                jmp RCX;
            }
        }
        else static if ( __traits( compiles, ucontext_t ) )
        {
            Fiber   cfib = Fiber.getThis();
            void*   ucur = cfib.m_ucur;

            *oldp = &ucur;
            swapcontext( **(cast(ucontext_t***) oldp),
                          *(cast(ucontext_t**)  newp) );
        }
        else
            static assert(0, "Not implemented");
    }
}


class Fiber : FiberBase
{
    ///////////////////////////////////////////////////////////////////////////
    // Initialization
    ///////////////////////////////////////////////////////////////////////////

    version (OSX)
    {
        version (X86_64)
            // libunwind on macOS 11 now requires more stack space than 16k, so
            // default to a larger stack size. This is only applied to X86 as
            // the pageSize is still 4k, however on AArch64 it is 16k.
            enum defaultStackPages = 8;
        else
            enum defaultStackPages = 4;
    }
    else
        enum defaultStackPages = 4;

    /**
     * Initializes a fiber object which is associated with a static
     * D function.
     *
     * Params:
     *  fn = The fiber function.
     *  sz = The stack size for this fiber.
     *  guardPageSize = size of the guard page to trap fiber's stack
     *                  overflows. Beware that using this will increase
     *                  the number of mmaped regions on platforms using mmap
     *                  so an OS-imposed limit may be hit.
     *
     * In:
     *  fn must not be null.
     */
    this( void function() fn, size_t sz = pageSize * defaultStackPages,
          size_t guardPageSize = pageSize ) nothrow
    {
        super( fn, sz, guardPageSize );
    }


    /**
     * Initializes a fiber object which is associated with a dynamic
     * D function.
     *
     * Params:
     *  dg = The fiber function.
     *  sz = The stack size for this fiber.
     *  guardPageSize = size of the guard page to trap fiber's stack
     *                  overflows. Beware that using this will increase
     *                  the number of mmaped regions on platforms using mmap
     *                  so an OS-imposed limit may be hit.
     *
     * In:
     *  dg must not be null.
     */
    this( void delegate() dg, size_t sz = pageSize * defaultStackPages,
          size_t guardPageSize = pageSize ) nothrow
    {
        super( dg, sz, guardPageSize );
    }


    ///////////////////////////////////////////////////////////////////////////
    // Fiber Accessors
    ///////////////////////////////////////////////////////////////////////////


    /**
     * Provides a reference to the calling fiber or null if no fiber is
     * currently active.
     *
     * Returns:
     *  The fiber object representing the calling fiber or null if no fiber
     *  is currently active within this thread. The result of deleting this object is undefined.
     */
    static Fiber getThis() @safe nothrow @nogc
    {
        // LDC NOTE:
        // Currently, it is not safe to migrate fibers across threads when they
        // use TLS at all, as LLVM might cache the TLS address lookup across a
        // context switch (see https://github.com/ldc-developers/ldc/issues/666).
        // Preventing inlining of this function, as well as switch{In,Out}
        // below, enables users to do this at least as long as they are very
        // careful about accessing TLS data themselves (such as in the shared
        // fiber unittest below, which tends to sporadically crash with enabled
        // optimizations if this prevent-inlining workaround is removed).
        version (LDC) pragma(inline, false);
        return cast(Fiber) FiberBase.getThis();
    }


    ///////////////////////////////////////////////////////////////////////////
    // Static Initialization
    ///////////////////////////////////////////////////////////////////////////


    version (all)
    {
        static this()
        {
            static if ( __traits( compiles, ucontext_t ) )
            {
              int status = getcontext( &sm_utxt );
              assert( status == 0 );
            }
        }
    }

protected:
    ///////////////////////////////////////////////////////////////////////////
    // Stack Management
    ///////////////////////////////////////////////////////////////////////////


    //
    // Allocate a new stack for this fiber.
    //
    final override void allocStack( size_t sz, size_t guardPageSize ) nothrow
    in
    {
        assert( !m_pmem && !m_ctxt );
    }
    do
    {
        // adjust alloc size to a multiple of pageSize
        sz += pageSize - 1;
        sz -= sz % pageSize;

        // NOTE: This instance of Thread.Context is dynamic so Fiber objects
        //       can be collected by the GC so long as no user level references
        //       to the object exist.  If m_ctxt were not dynamic then its
        //       presence in the global context list would be enough to keep
        //       this object alive indefinitely.  An alternative to allocating
        //       room for this struct explicitly would be to mash it into the
        //       base of the stack being allocated below.  However, doing so
        //       requires too much special logic to be worthwhile.

        import core.memory : GC;
        m_ctxt = new StackContext;

        version (SupportSanitizers)
        {
            // m_curThread is not initialized yet, so we have to wait with storing this StackContext's asan_fakestack handler until switchIn is called.
        }

        version (all)
        {
            version (Posix) import core.sys.posix.sys.mman; // mmap, MAP_ANON
            import core.stdc.stdlib : malloc; // available everywhere

            static if ( __traits( compiles, ucontext_t ) )
            {
                // Stack size must be at least the minimum allowable by the OS.
                if (sz < MINSIGSTKSZ)
                    sz = MINSIGSTKSZ;
            }

            static if ( __traits( compiles, mmap ) )
            {
                // Allocate more for the memory guard
                sz += guardPageSize;

                int mmap_flags = MAP_PRIVATE | MAP_ANON;
                version (OpenBSD)
                    mmap_flags |= MAP_STACK;

                m_pmem = mmap( null,
                               sz,
                               PROT_READ | PROT_WRITE,
                               mmap_flags,
                               -1,
                               0 );
                if ( m_pmem == MAP_FAILED )
                    m_pmem = null;
            }
            else static if ( __traits( compiles, valloc ) )
            {
                m_pmem = valloc( sz );
            }
            else
            {
                import core.stdc.stdlib : malloc;

                m_pmem = malloc( sz );
            }

            if ( !m_pmem )
                onOutOfMemoryError();

            static if (isStackGrowingDown)
            {
                m_ctxt.bstack = m_pmem + sz;
                m_ctxt.tstack = m_pmem + sz;
                void* guard = m_pmem;
            }
            else
            {
                m_ctxt.bstack = m_pmem;
                m_ctxt.tstack = m_pmem;
                void* guard = m_pmem + sz - guardPageSize;
            }
            m_size = sz;

            static if ( __traits( compiles, mmap ) )
            {
                if (guardPageSize)
                {
                    // protect end of stack
                    if ( mprotect(guard, guardPageSize, PROT_NONE) == -1 )
                        abort();
                }
            }
            else
            {
                // Supported only for mmap allocated memory - results are
                // undefined if applied to memory not obtained by mmap
            }
        }

        ThreadBase.add( m_ctxt );
    }


    //
    // Free this fiber's stack.
    //
    final override void freeStack() nothrow @nogc
    in(m_pmem)
    in(m_ctxt)
    {
        // NOTE: m_ctxt is guaranteed to be alive because it is held in the
        //       global context list.
        ThreadBase.slock.lock_nothrow();
        scope(exit) ThreadBase.slock.unlock_nothrow();
        ThreadBase.remove( m_ctxt );

        version (all)
        {
            import core.sys.posix.sys.mman; // munmap
            import core.stdc.stdlib : free;

            static if ( __traits( compiles, mmap ) )
            {
                munmap( m_pmem, m_size );
            }
            else
            {
                free( m_pmem );
            }
        }
        m_pmem = null;
        m_ctxt = null;
    }


    //
    // Initialize the allocated stack.
    // Look above the definition of 'class Fiber' for some information about the implementation of this routine
    //
    final override void initStack() nothrow @nogc
    in
    {
        assert( m_ctxt.tstack && m_ctxt.tstack == m_ctxt.bstack );
        assert( cast(size_t) m_ctxt.bstack % (void*).sizeof == 0 );
    }
    do
    {
        version (all)
        {
            void* pstack = m_ctxt.tstack;
            scope( exit )  m_ctxt.tstack = pstack;

            void push( size_t val ) nothrow
            {
                static if (isStackGrowingDown)
                {
                    pstack -= size_t.sizeof;
                    *(cast(size_t*) pstack) = val;
                }
                else
                {
                    pstack += size_t.sizeof;
                    *(cast(size_t*) pstack) = val;
                }
            }
        }

        // NOTE: On OS X the stack must be 16-byte aligned according
        // to the IA-32 call spec. For x86_64 the stack also needs to
        // be aligned to 16-byte according to SysV AMD64 ABI.
        version (AlignFiberStackTo16Byte)
        {
            static if (isStackGrowingDown)
            {
                pstack = cast(void*)(cast(size_t)(pstack) - (cast(size_t)(pstack) & 0x0F));
            }
            else
            {
                pstack = cast(void*)(cast(size_t)(pstack) + (cast(size_t)(pstack) & 0x0F));
            }
        }

        version (AsmX86_Posix)
        {
            push( 0x00000000 );                                     // Return address of fiber_entryPoint call
            push( cast(size_t) &fiber_entryPoint );                 // EIP
            push( cast(size_t) m_ctxt.bstack );                     // EBP
            push( 0x00000000 );                                     // EDI
            push( 0x00000000 );                                     // ESI
            push( 0x00000000 );                                     // EBX
            push( 0x00000000 );                                     // EAX
        }
        else version (AsmX86_64_Posix)
        {
            push( 0x00000000_00000000 );                            // Return address of fiber_entryPoint call
            push( cast(size_t) &fiber_entryPoint );                 // RIP
            push( cast(size_t) m_ctxt.bstack );                     // RBP
            push( 0x00000000_00000000 );                            // RBX
            push( 0x00000000_00000000 );                            // R12
            push( 0x00000000_00000000 );                            // R13
            push( 0x00000000_00000000 );                            // R14
            push( 0x00000000_00000000 );                            // R15
        }
        else version (AsmPPC_Posix)
        {
            static if (isStackGrowingDown)
            {
                pstack -= int.sizeof * 5;
            }
            else
            {
                pstack += int.sizeof * 5;
            }

            push( cast(size_t) &fiber_entryPoint );     // link register
            push( 0x00000000 );                         // control register
            push( 0x00000000 );                         // old stack pointer

            // GPR values
            static if (isStackGrowingDown)
            {
                pstack -= int.sizeof * 20;
            }
            else
            {
                pstack += int.sizeof * 20;
            }

            assert( (cast(size_t) pstack & 0x0f) == 0 );
        }
        else version (AsmPPC64_Posix)
        {
            static if (isStackGrowingDown) {}
            else static assert(0);

            /*
             * The stack frame uses the standard layout except for floating
             * point and vector registers.
             *
             * ELFv2:
             * +------------------------+
             * | TOC Pointer Doubleword | SP+24
             * +------------------------+
             * | LR Save Doubleword     | SP+16
             * +------------------------+
             * | Reserved               | SP+12
             * +------------------------+
             * | CR Save Word           | SP+8
             * +------------------------+
             * | Back Chain             | SP+176 <-- Previous function
             * +------------------------+
             * | GPR Save Area (14-31)  | SP+32
             * +------------------------+
             * | TOC Pointer Doubleword | SP+24
             * +------------------------+
             * | LR Save Doubleword     | SP+16
             * +------------------------+
             * | Reserved               | SP+12
             * +------------------------+
             * | CR Save Word           | SP+8
             * +------------------------+
             * | Back Chain             | SP+0   <-- Stored stack pointer
             * +------------------------+
             * | VR Save Area (20-31)   | SP-16
             * +------------------------+
             * | FPR Save Area (14-31)  | SP-200
             * +------------------------+
             *
             * ELFv1:
             * +------------------------+
             * | Parameter Save Area    | SP+48
             * +------------------------+
             * | TOC Pointer Doubleword | SP+40
             * +------------------------+
             * | Link editor doubleword | SP+32
             * +------------------------+
             * | Compiler Doubleword    | SP+24
             * +------------------------+
             * | LR Save Doubleword     | SP+16
             * +------------------------+
             * | Reserved               | SP+12
             * +------------------------+
             * | CR Save Word           | SP+8
             * +------------------------+
             * | Back Chain             | SP+256 <-- Previous function
             * +------------------------+
             * | GPR Save Area (14-31)  | SP+112
             * +------------------------+
             * | Parameter Save Area    | SP+48
             * +------------------------+
             * | TOC Pointer Doubleword | SP+40
             * +------------------------+
             * | Link editor doubleword | SP+32
             * +------------------------+
             * | Compiler Doubleword    | SP+24
             * +------------------------+
             * | LR Save Doubleword     | SP+16
             * +------------------------+
             * | Reserved               | SP+12
             * +------------------------+
             * | CR Save Word           | SP+8
             * +------------------------+
             * | Back Chain             | SP+0   <-- Stored stack pointer
             * +------------------------+
             * | VR Save Area (20-31)   | SP-16
             * +------------------------+
             * | FPR Save Area (14-31)  | SP-200
             * +------------------------+
             */
            assert( (cast(size_t) pstack & 0x0f) == 0 );
            version (ELFv1)
            {
                pstack -= size_t.sizeof * 8;                // Parameter Save Area
                push( 0x00000000_00000000 );                // TOC Pointer Doubleword
                push( 0x00000000_00000000 );                // Link editor doubleword
                push( 0x00000000_00000000 );                // Compiler Doubleword
                push( cast(size_t) &fiber_entryPoint );     // LR Save Doubleword
                push( 0x00000000_00000000 );                // CR Save Word
                push( 0x00000000_00000000 );                // Back Chain
                size_t backchain = cast(size_t) pstack;     // Save back chain
                pstack -= size_t.sizeof * 18;               // GPR Save Area
                pstack -= size_t.sizeof * 8;                // Parameter Save Area
                push( 0x00000000_00000000 );                // TOC Pointer Doubleword
                push( 0x00000000_00000000 );                // Link editor doubleword
                push( 0x00000000_00000000 );                // Compiler Doubleword
                push( 0x00000000_00000000 );                // LR Save Doubleword
                push( 0x00000000_00000000 );                // CR Save Word
                push( backchain );                          // Back Chain
            }
            else
            {
                push( 0x00000000_00000000 );                // TOC Pointer Doubleword
                push( cast(size_t) &fiber_entryPoint );     // LR Save Doubleword
                push( 0x00000000_00000000 );                // CR Save Word
                push( 0x00000000_00000000 );                // Back Chain
                size_t backchain = cast(size_t) pstack;     // Save back chain
                pstack -= size_t.sizeof * 18;               // GPR Save Area
                push( 0x00000000_00000000 );                // TOC Pointer Doubleword
                push( 0x00000000_00000000 );                // LR Save Doubleword
                push( 0x00000000_00000000 );                // CR Save Word
                push( backchain );                          // Back Chain
            }
            assert( (cast(size_t) pstack & 0x0f) == 0 );
        }
        else version (AsmPPC_Darwin)
        {
            static if (isStackGrowingDown) {}
            else static assert(false, "PowerPC Darwin only supports decrementing stacks");

            uint wsize = size_t.sizeof;

            // linkage + regs + FPRs + VRs
            uint space = 8 * wsize + 20 * wsize + 18 * 8 + 12 * 16;
            (cast(ubyte*)pstack - space)[0 .. space] = 0;

            pstack -= wsize * 6;
            *cast(size_t*)pstack = cast(size_t) &fiber_entryPoint; // LR
            pstack -= wsize * 22;

            // On Darwin PPC64 pthread self is in R13 (which is reserved).
            // At present, it is not safe to migrate fibers between threads, but if that
            // changes, then updating the value of R13 will also need to be handled.
            version (PPC64)
              *cast(size_t*)(pstack + wsize) = cast(size_t) ThreadBase.getThis().m_addr;
            assert( (cast(size_t) pstack & 0x0f) == 0 );
        }
        else version (AsmMIPS_O32_Posix)
        {
            static if (isStackGrowingDown) {}
            else static assert(0);

            /* We keep the FP registers and the return address below
             * the stack pointer, so they don't get scanned by the
             * GC. The last frame before swapping the stack pointer is
             * organized like the following.
             *
             *     |-----------|<= frame pointer
             *     |    $gp    |
             *     |   $s0-8   |
             *     |-----------|<= stack pointer
             *     |    $ra    |
             *     |  align(8) |
             *     |  $f20-30  |
             *     |-----------|
             *
             */
            enum SZ_GP = 10 * size_t.sizeof; // $gp + $s0-8
            enum SZ_RA = size_t.sizeof;      // $ra
            version (MIPS_HardFloat)
            {
                enum SZ_FP = 6 * 8;          // $f20-30
                enum ALIGN = -(SZ_FP + SZ_RA) & (8 - 1);
            }
            else
            {
                enum SZ_FP = 0;
                enum ALIGN = 0;
            }

            enum BELOW = SZ_FP + ALIGN + SZ_RA;
            enum ABOVE = SZ_GP;
            enum SZ = BELOW + ABOVE;

            (cast(ubyte*)pstack - SZ)[0 .. SZ] = 0;
            pstack -= ABOVE;
            *cast(size_t*)(pstack - SZ_RA) = cast(size_t)&fiber_entryPoint;
        }
        else version (AsmMIPS_N64_Posix)
        {
            static if (isStackGrowingDown) {}
            else static assert(0);

            /* We keep the FP registers and the return address below
             * the stack pointer, so they don't get scanned by the
             * GC. The last frame before swapping the stack pointer is
             * organized like the following.
             *
             *     |-----------|<= frame pointer
             *     |  $fp/$gp  |
             *     |   $s0-7   |
             *     |-----------|<= stack pointer
             *     |    $ra    |
             *     |  $f24-31  |
             *     |-----------|
             *
             */
            enum SZ_GP = 10 * size_t.sizeof; // $fp + $gp + $s0-7
            enum SZ_RA = size_t.sizeof;      // $ra
            version (MIPS_HardFloat)
            {
                enum SZ_FP = 8 * double.sizeof; // $f24-31
            }
            else
            {
                enum SZ_FP = 0;
            }

            enum BELOW = SZ_FP + SZ_RA;
            enum ABOVE = SZ_GP;
            enum SZ = BELOW + ABOVE;

            (cast(ubyte*)pstack - SZ)[0 .. SZ] = 0;
            pstack -= ABOVE;
            *cast(size_t*)(pstack - SZ_RA) = cast(size_t)&fiber_entryPoint;
        }
        else version (AsmLoongArch64_Posix)
        {
            // Like others, FP registers and return address ($r1) are kept
            // below the saved stack top (tstack) to hide from GC scanning.
            // fiber_switchContext expects newp sp to look like this:
            //    9: $r22 (frame pointer)
            //    8: $r23
            //   ...
            //    0: $r31 <-- newp tstack
            //   -1: $r1  (return address)  [&fiber_entryPoint]
            //   -2: $f24
            //   ...
            //   -9: $f31

            static if (isStackGrowingDown) {}
            else
                static assert(false, "Only full descending stacks supported on LoongArch64");

            // Only need to set return address ($r1).  Everything else is fine
            // zero initialized.
            pstack -= size_t.sizeof * 10;    // skip past space reserved for $r22-$r31
            push(cast(size_t) &fiber_trampoline); // see threadasm.S for docs
            pstack += size_t.sizeof;         // adjust sp (newp) above lr
        }
        else version (AsmAArch64_Posix)
        {
            // Like others, FP registers and return address (lr) are kept
            // below the saved stack top (tstack) to hide from GC scanning.
            // fiber_switchContext expects newp sp to look like this:
            //   19: x19
            //   ...
            //    9: x29 (fp)  <-- newp tstack
            //    8: x30 (lr)  [&fiber_entryPoint]
            //    7: d8
            //   ...
            //    0: d15

            static if (isStackGrowingDown) {}
            else
                static assert(false, "Only full descending stacks supported on AArch64");

            // Only need to set return address (lr).  Everything else is fine
            // zero initialized.
            pstack -= size_t.sizeof * 11;    // skip past x19-x29
            push(cast(size_t) &fiber_trampoline); // see threadasm.S for docs
            pstack += size_t.sizeof;         // adjust sp (newp) above lr
        }
        else version (AsmARM_Posix)
        {
            /* We keep the FP registers and the return address below
             * the stack pointer, so they don't get scanned by the
             * GC. The last frame before swapping the stack pointer is
             * organized like the following.
             *
             *   |  |-----------|<= 'frame starts here'
             *   |  |     fp    | (the actual frame pointer, r11 isn't
             *   |  |   r10-r4  |  updated and still points to the previous frame)
             *   |  |-----------|<= stack pointer
             *   |  |     lr    |
             *   |  | 4byte pad |
             *   |  |   d15-d8  |(if FP supported)
             *   |  |-----------|
             *   Y
             *   stack grows down: The pointer value here is smaller than some lines above
             */
            // frame pointer can be zero, r10-r4 also zero initialized
            static if (isStackGrowingDown)
                pstack -= int.sizeof * 8;
            else
                static assert(false, "Only full descending stacks supported on ARM");

            // link register
            push( cast(size_t) &fiber_entryPoint );
            /*
             * We do not push padding and d15-d8 as those are zero initialized anyway
             * Position the stack pointer above the lr register
             */
            pstack += int.sizeof * 1;
        }
        else static if ( __traits( compiles, ucontext_t ) )
        {
            getcontext( &m_utxt );
            m_utxt.uc_stack.ss_sp   = m_pmem;
            m_utxt.uc_stack.ss_size = m_size;
            makecontext( &m_utxt, &fiber_entryPoint, 0 );
            // NOTE: If ucontext is being used then the top of the stack will
            //       be a pointer to the ucontext_t struct for that fiber.
            push( cast(size_t) &m_utxt );
        }
        else
            static assert(0, "Not implemented");
    }
}

version (D_InlineAsm_X86_64)
{
    unittest
    {
        void testStackAlignment()
        {
            void* pRSP;
            asm pure nothrow @nogc
            {
                mov pRSP, RSP;
            }
            assert((cast(size_t)pRSP & 0xF) == 0);
        }

        auto fib = new Fiber(&testStackAlignment);
        fib.call();
    }
}
