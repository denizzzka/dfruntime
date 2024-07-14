/**
 * The fiber module provides OS-indepedent lightweight threads aka fibers.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak
 * Source:    $(DRUNTIMESRC core/thread/fiber.d)
 */

module core.thread.fiber;

import core.thread.fiber.base: FiberBase, fiber_entryPoint;
import core.thread.threadbase;
import core.thread.threadgroup;
import core.thread.types;
import core.thread.context;

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

version (GNU)
{
    import gcc.builtins;
    version (GNU_StackGrowsDown)
        version = StackGrowsDown;
}
else
{
    // this should be true for most architectures
    version = StackGrowsDown;
}

version (Windows)
{
    import core.stdc.stdlib : malloc, free;
    import core.sys.windows.winbase;
    import core.sys.windows.winnt;
}

package
{
    version (D_InlineAsm_X86)
    {
        version (Windows)
            version = AsmX86_Windows;
        else version (Posix)
            version = AsmX86_Posix;

        version = AlignFiberStackTo16Byte;
    }
    else version (D_InlineAsm_X86_64)
    {
        version (Windows)
        {
            version = AsmX86_64_Windows;
            version = AlignFiberStackTo16Byte;
        }
        else version (Posix)
        {
            version = AsmX86_64_Posix;
            version = AlignFiberStackTo16Byte;
        }
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
        version (AsmX86_Windows)    {} else
        version (AsmX86_Posix)      {} else
        version (AsmX86_64_Windows) {} else
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
  else version (LDC_Windows)
  {
    extern (C) void fiber_switchContext( void** oldp, void* newp ) nothrow @nogc @naked
    {
        version (X86)
        {
            pragma(LDC_never_inline);

            __asm(
               `// save current stack state
                push %ebp
                mov  %esp, %ebp
                push %edi
                push %esi
                push %ebx
                push %fs:(0)
                push %fs:(4)
                push %fs:(8)
                push %eax

                // store oldp again with more accurate address
                mov 8(%ebp), %eax
                mov %esp, (%eax)
                // load newp to begin context switch
                mov 12(%ebp), %esp

                // load saved state from new stack
                pop %eax
                pop %fs:(8)
                pop %fs:(4)
                pop %fs:(0)
                pop %ebx
                pop %esi
                pop %edi
                pop %ebp

                // 'return' to complete switch
                pop %ecx
                jmp *%ecx`,
                "~{memory},~{ebp},~{esp},~{eax},~{ebx},~{ecx},~{esi},~{edi}"
            );
        }
        else version (X86_64)
        {
            // This inline asm assumes a return address has been pushed onto the stack
            // (and so a stack not aligned to 16 bytes).
            pragma(LDC_never_inline);

            __asm(
               `// save current stack state
                push %rbp
                mov  %rsp, %rbp
                push %r12
                push %r13
                push %r14
                push %r15
                push %rdi
                push %rsi
                // 7 registers = 56 bytes; stack is now aligned to 16 bytes
                sub $$0xA0, %rsp
                movdqa %xmm6, 0x90(%rsp)
                movdqa %xmm7, 0x80(%rsp)
                movdqa %xmm8, 0x70(%rsp)
                movdqa %xmm9, 0x60(%rsp)
                movdqa %xmm10, 0x50(%rsp)
                movdqa %xmm11, 0x40(%rsp)
                movdqa %xmm12, 0x30(%rsp)
                movdqa %xmm13, 0x20(%rsp)
                movdqa %xmm14, 0x10(%rsp)
                movdqa %xmm15, (%rsp)
                push %rbx
                xor  %rax, %rax
                push %gs:(%rax)
                push %gs:8(%rax)
                push %gs:16(%rax)

                // store oldp
                mov %rsp, (%rcx)
                // load newp to begin context switch
                mov %rdx, %rsp

                // load saved state from new stack
                pop %gs:16(%rax)
                pop %gs:8(%rax)
                pop %gs:(%rax)
                pop %rbx;
                movdqa (%rsp), %xmm15
                movdqa 0x10(%rsp), %xmm14
                movdqa 0x20(%rsp), %xmm13
                movdqa 0x30(%rsp), %xmm12
                movdqa 0x40(%rsp), %xmm11
                movdqa 0x50(%rsp), %xmm10
                movdqa 0x60(%rsp), %xmm9
                movdqa 0x70(%rsp), %xmm8
                movdqa 0x80(%rsp), %xmm7
                movdqa 0x90(%rsp), %xmm6
                add $$0xA0, %rsp
                pop %rsi
                pop %rdi
                pop %r15
                pop %r14
                pop %r13
                pop %r12
                pop %rbp

                // 'return' to complete switch
                pop %rcx
                jmp *%rcx`,
                "~{memory},~{rbp},~{rsp},~{rax},~{rbx},~{rcx},~{rsi},~{rdi},~{r12},~{r13},~{r14},~{r15}," ~
                "~{xmm6},~{xmm7},~{xmm8},~{xmm9},~{xmm10},~{xmm11},~{xmm12},~{xmm13},~{xmm14},~{xmm15}"
            );
        }
        else
            static assert(false);
    }
  }
  else
    extern (C) void fiber_switchContext( void** oldp, void* newp ) nothrow @nogc
    {
        // NOTE: The data pushed and popped in this routine must match the
        //       default stack created by Fiber.initStack or the initial
        //       switch into a new context will fail.

        version (AsmX86_Windows)
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
                push dword ptr FS:[0];
                push dword ptr FS:[4];
                push dword ptr FS:[8];
                push EAX;

                // store oldp again with more accurate address
                mov EAX, dword ptr 8[EBP];
                mov [EAX], ESP;
                // load newp to begin context switch
                mov ESP, dword ptr 12[EBP];

                // load saved state from new stack
                pop EAX;
                pop dword ptr FS:[8];
                pop dword ptr FS:[4];
                pop dword ptr FS:[0];
                pop EBX;
                pop ESI;
                pop EDI;
                pop EBP;

                // 'return' to complete switch
                pop ECX;
                jmp ECX;
            }
        }
        else version (AsmX86_64_Windows)
        {
            asm pure nothrow @nogc
            {
                naked;

                // save current stack state
                // NOTE: When changing the layout of registers on the stack,
                //       make sure that the XMM registers are still aligned.
                //       On function entry, the stack is guaranteed to not
                //       be aligned to 16 bytes because of the return address
                //       on the stack.
                push RBP;
                mov  RBP, RSP;
                push R12;
                push R13;
                push R14;
                push R15;
                push RDI;
                push RSI;
                // 7 registers = 56 bytes; stack is now aligned to 16 bytes
                sub RSP, 160;
                movdqa [RSP + 144], XMM6;
                movdqa [RSP + 128], XMM7;
                movdqa [RSP + 112], XMM8;
                movdqa [RSP + 96], XMM9;
                movdqa [RSP + 80], XMM10;
                movdqa [RSP + 64], XMM11;
                movdqa [RSP + 48], XMM12;
                movdqa [RSP + 32], XMM13;
                movdqa [RSP + 16], XMM14;
                movdqa [RSP], XMM15;
                push RBX;
                xor  RAX,RAX;
                push qword ptr GS:[RAX];
                push qword ptr GS:8[RAX];
                push qword ptr GS:16[RAX];

                // store oldp
                mov [RCX], RSP;
                // load newp to begin context switch
                mov RSP, RDX;

                // load saved state from new stack
                pop qword ptr GS:16[RAX];
                pop qword ptr GS:8[RAX];
                pop qword ptr GS:[RAX];
                pop RBX;
                movdqa XMM15, [RSP];
                movdqa XMM14, [RSP + 16];
                movdqa XMM13, [RSP + 32];
                movdqa XMM12, [RSP + 48];
                movdqa XMM11, [RSP + 64];
                movdqa XMM10, [RSP + 80];
                movdqa XMM9, [RSP + 96];
                movdqa XMM8, [RSP + 112];
                movdqa XMM7, [RSP + 128];
                movdqa XMM6, [RSP + 144];
                add RSP, 160;
                pop RSI;
                pop RDI;
                pop R15;
                pop R14;
                pop R13;
                pop R12;
                pop RBP;

                // 'return' to complete switch
                pop RCX;
                jmp RCX;
            }
        }
        else version (AsmX86_Posix)
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

    version (Windows)
        // exception handling walks the stack, invoking DbgHelp.dll which
        // needs up to 16k of stack space depending on the version of DbgHelp.dll,
        // the existence of debug symbols and other conditions. Avoid causing
        // stack overflows by defaulting to a larger stack size
        enum defaultStackPages = 8;
    else version (OSX)
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


    version (Posix)
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

        version (Windows)
        {
            // reserve memory for stack
            m_pmem = VirtualAlloc( null,
                                   sz + guardPageSize,
                                   MEM_RESERVE,
                                   PAGE_NOACCESS );
            if ( !m_pmem )
                onOutOfMemoryError();

            version (StackGrowsDown)
            {
                void* stack = m_pmem + guardPageSize;
                void* guard = m_pmem;
                void* pbase = stack + sz;
            }
            else
            {
                void* stack = m_pmem;
                void* guard = m_pmem + sz;
                void* pbase = stack;
            }

            // allocate reserved stack segment
            stack = VirtualAlloc( stack,
                                  sz,
                                  MEM_COMMIT,
                                  PAGE_READWRITE );
            if ( !stack )
                onOutOfMemoryError();

            if (guardPageSize)
            {
                // allocate reserved guard page
                guard = VirtualAlloc( guard,
                                      guardPageSize,
                                      MEM_COMMIT,
                                      PAGE_READWRITE | PAGE_GUARD );
                if ( !guard )
                    onOutOfMemoryError();
            }

            m_ctxt.bstack = pbase;
            m_ctxt.tstack = pbase;
            m_size = sz;
        }
        else
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

            version (StackGrowsDown)
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

        version (Windows)
        {
            VirtualFree( m_pmem, 0, MEM_RELEASE );
        }
        else
        {
            version (Posix) import core.sys.posix.sys.mman; // munmap
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
        version (DruntimeAbstractRt) {} else
        {
            void* pstack = m_ctxt.tstack;
            scope( exit )  m_ctxt.tstack = pstack;

            void push( size_t val ) nothrow
            {
                version (StackGrowsDown)
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
            version (StackGrowsDown)
            {
                pstack = cast(void*)(cast(size_t)(pstack) - (cast(size_t)(pstack) & 0x0F));
            }
            else
            {
                pstack = cast(void*)(cast(size_t)(pstack) + (cast(size_t)(pstack) & 0x0F));
            }
        }

        version (DruntimeAbstractRt)
        {
            import external.core.fiber : initStack;

            version(StackGrowsDown)
                initStack!true(m_ctxt);
            else
                initStack!false(m_ctxt);
        }
        else
        version (AsmX86_Windows)
        {
            version (StackGrowsDown) {} else static assert( false );

            // On Windows Server 2008 and 2008 R2, an exploit mitigation
            // technique known as SEHOP is activated by default. To avoid
            // hijacking of the exception handler chain, the presence of a
            // Windows-internal handler (ntdll.dll!FinalExceptionHandler) at
            // its end is tested by RaiseException. If it is not present, all
            // handlers are disregarded, and the program is thus aborted
            // (see http://blogs.technet.com/b/srd/archive/2009/02/02/
            // preventing-the-exploitation-of-seh-overwrites-with-sehop.aspx).
            // For new threads, this handler is installed by Windows immediately
            // after creation. To make exception handling work in fibers, we
            // have to insert it for our new stacks manually as well.
            //
            // To do this, we first determine the handler by traversing the SEH
            // chain of the current thread until its end, and then construct a
            // registration block for the last handler on the newly created
            // thread. We then continue to push all the initial register values
            // for the first context switch as for the other implementations.
            //
            // Note that this handler is never actually invoked, as we install
            // our own one on top of it in the fiber entry point function.
            // Thus, it should not have any effects on OSes not implementing
            // exception chain verification.

            alias fp_t = void function(); // Actual signature not relevant.
            static struct EXCEPTION_REGISTRATION
            {
                EXCEPTION_REGISTRATION* next; // sehChainEnd if last one.
                fp_t handler;
            }
            enum sehChainEnd = cast(EXCEPTION_REGISTRATION*) 0xFFFFFFFF;

            __gshared static fp_t finalHandler = null;
            if ( finalHandler is null )
            {
                version (LDC)
                {
                    static EXCEPTION_REGISTRATION* fs0() nothrow @naked
                    {
                        return __asm!(EXCEPTION_REGISTRATION*)("mov %fs:(0), $0", "=r");
                    }
                }
                else
                {
                    static EXCEPTION_REGISTRATION* fs0() nothrow
                    {
                        asm pure nothrow @nogc
                        {
                            naked;
                            mov EAX, FS:[0];
                            ret;
                        }
                    }
                }

                auto reg = fs0();
                while ( reg.next != sehChainEnd ) reg = reg.next;

                // Benign races are okay here, just to avoid re-lookup on every
                // fiber creation.
                finalHandler = reg.handler;
            }

            // When linking with /safeseh (supported by LDC, but not DMD)
            // the exception chain must not extend to the very top
            // of the stack, otherwise the exception chain is also considered
            // invalid. Reserving additional 4 bytes at the top of the stack will
            // keep the EXCEPTION_REGISTRATION below that limit
            size_t reserve = EXCEPTION_REGISTRATION.sizeof + 4;
            pstack -= reserve;
            *(cast(EXCEPTION_REGISTRATION*)pstack) =
                EXCEPTION_REGISTRATION( sehChainEnd, finalHandler );
            auto pChainEnd = pstack;

            push( cast(size_t) &fiber_entryPoint );                 // EIP
            push( cast(size_t) m_ctxt.bstack - reserve );           // EBP
            push( 0x00000000 );                                     // EDI
            push( 0x00000000 );                                     // ESI
            push( 0x00000000 );                                     // EBX
            push( cast(size_t) pChainEnd );                         // FS:[0]
            push( cast(size_t) m_ctxt.bstack );                     // FS:[4]
            push( cast(size_t) m_ctxt.bstack - m_size );            // FS:[8]
            push( 0x00000000 );                                     // EAX
        }
        else version (AsmX86_64_Windows)
        {
            // Using this trampoline instead of the raw fiber_entryPoint
            // ensures that during context switches, source and destination
            // stacks have the same alignment. Otherwise, the stack would need
            // to be shifted by 8 bytes for the first call, as fiber_entryPoint
            // is an actual function expecting a stack which is not aligned
            // to 16 bytes.
            version (LDC)
            {
                static void trampoline() @naked
                {
                    __asm(
                       `sub $$32, %rsp
                        call fiber_entryPoint
                        xor %rcx, %rcx
                        jmp *%rcx`,
                        "~{rsp},~{rcx}"
                    );
                }
            }
            else
            {
                static void trampoline()
                {
                    asm pure nothrow @nogc
                    {
                        naked;
                        sub RSP, 32; // Shadow space (Win64 calling convention)
                        call fiber_entryPoint;
                        xor RCX, RCX; // This should never be reached, as
                        jmp RCX;      // fiber_entryPoint must never return.
                    }
                }
            }

            push( cast(size_t) &trampoline );                       // RIP
            push( 0x00000000_00000000 );                            // RBP
            push( 0x00000000_00000000 );                            // R12
            push( 0x00000000_00000000 );                            // R13
            push( 0x00000000_00000000 );                            // R14
            push( 0x00000000_00000000 );                            // R15
            push( 0x00000000_00000000 );                            // RDI
            push( 0x00000000_00000000 );                            // RSI
            push( 0x00000000_00000000 );                            // XMM6 (high)
            push( 0x00000000_00000000 );                            // XMM6 (low)
            push( 0x00000000_00000000 );                            // XMM7 (high)
            push( 0x00000000_00000000 );                            // XMM7 (low)
            push( 0x00000000_00000000 );                            // XMM8 (high)
            push( 0x00000000_00000000 );                            // XMM8 (low)
            push( 0x00000000_00000000 );                            // XMM9 (high)
            push( 0x00000000_00000000 );                            // XMM9 (low)
            push( 0x00000000_00000000 );                            // XMM10 (high)
            push( 0x00000000_00000000 );                            // XMM10 (low)
            push( 0x00000000_00000000 );                            // XMM11 (high)
            push( 0x00000000_00000000 );                            // XMM11 (low)
            push( 0x00000000_00000000 );                            // XMM12 (high)
            push( 0x00000000_00000000 );                            // XMM12 (low)
            push( 0x00000000_00000000 );                            // XMM13 (high)
            push( 0x00000000_00000000 );                            // XMM13 (low)
            push( 0x00000000_00000000 );                            // XMM14 (high)
            push( 0x00000000_00000000 );                            // XMM14 (low)
            push( 0x00000000_00000000 );                            // XMM15 (high)
            push( 0x00000000_00000000 );                            // XMM15 (low)
            push( 0x00000000_00000000 );                            // RBX
            push( 0xFFFFFFFF_FFFFFFFF );                            // GS:[0]
            version (StackGrowsDown)
            {
                push( cast(size_t) m_ctxt.bstack );                 // GS:[8]
                push( cast(size_t) m_ctxt.bstack - m_size );        // GS:[16]
            }
            else
            {
                push( cast(size_t) m_ctxt.bstack );                 // GS:[8]
                push( cast(size_t) m_ctxt.bstack + m_size );        // GS:[16]
            }
        }
        else version (AsmX86_Posix)
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
            version (StackGrowsDown)
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
            version (StackGrowsDown)
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
            version (StackGrowsDown) {}
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
            version (StackGrowsDown) {}
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
            version (StackGrowsDown) {}
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
            version (StackGrowsDown) {}
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

            version (StackGrowsDown) {}
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

            version (StackGrowsDown) {}
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
            version (StackGrowsDown)
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


version (AsmX86_64_Windows)
{
    // Test Windows x64 calling convention
    unittest
    {
        void testNonvolatileRegister(alias REG)()
        {
            auto zeroRegister = new Fiber(() {
                mixin("asm pure nothrow @nogc { naked; xor "~REG~", "~REG~"; ret; }");
            });
            long after;

            mixin("asm pure nothrow @nogc { mov "~REG~", 0xFFFFFFFFFFFFFFFF; }");
            zeroRegister.call();
            mixin("asm pure nothrow @nogc { mov after, "~REG~"; }");

            assert(after == -1);
        }

        void testNonvolatileRegisterSSE(alias REG)()
        {
            auto zeroRegister = new Fiber(() {
                mixin("asm pure nothrow @nogc { naked; xorpd "~REG~", "~REG~"; ret; }");
            });
            long[2] before = [0xFFFFFFFF_FFFFFFFF, 0xFFFFFFFF_FFFFFFFF], after;

            mixin("asm pure nothrow @nogc { movdqu "~REG~", before; }");
            zeroRegister.call();
            mixin("asm pure nothrow @nogc { movdqu after, "~REG~"; }");

            assert(before == after);
        }

        testNonvolatileRegister!("R12")();
        testNonvolatileRegister!("R13")();
        testNonvolatileRegister!("R14")();
        testNonvolatileRegister!("R15")();
      version (LDC)
      {
        // FIXME: fails with `-O` (unless in separate object file)
      }
      else
      {
        testNonvolatileRegister!("RDI")();
        testNonvolatileRegister!("RSI")();
        testNonvolatileRegister!("RBX")();
      }

        testNonvolatileRegisterSSE!("XMM6")();
        testNonvolatileRegisterSSE!("XMM7")();
        testNonvolatileRegisterSSE!("XMM8")();
        testNonvolatileRegisterSSE!("XMM9")();
        testNonvolatileRegisterSSE!("XMM10")();
        testNonvolatileRegisterSSE!("XMM11")();
        testNonvolatileRegisterSSE!("XMM12")();
        testNonvolatileRegisterSSE!("XMM13")();
        testNonvolatileRegisterSSE!("XMM14")();
        testNonvolatileRegisterSSE!("XMM15")();
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
