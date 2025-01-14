/**
 * The osthread module provides low-level, OS-dependent code
 * for thread creation and management.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak
 * Source:    $(DRUNTIMESRC core/thread/osthread.d)
 */

module core.thread.osthread;

public import core.thread.common;
import core.thread.threadbase;
import core.thread.context;
import core.thread.types;
import core.atomic;
import core.memory : GC, pageSize;
import core.time;
import core.exception : onOutOfMemoryError;
import core.internal.traits : externDFunc;

// Here the entire file is version (Windows), but I don't remove most of
// these version branches so as not to distort code and not to complicate
// future upstream merges.
//
// Some version (Windows) renamed to version (all) to further protection from errors

version (LDC)
{
    import ldc.attributes;
    import ldc.llvmasm;

    version (Windows) version = LDC_Windows;

    version (ARM)     version = ARM_Any;
    version (AArch64) version = ARM_Any;

    version (MIPS32) version = MIPS_Any;
    version (MIPS64) version = MIPS_Any;

    version (PPC)   version = PPC_Any;
    version (PPC64) version = PPC_Any;

    version (RISCV32) version = RISCV_Any;
    version (RISCV64) version = RISCV_Any;

    version (SupportSanitizers)
    {
        import ldc.sanitizers_optionally_linked;
    }
}


///////////////////////////////////////////////////////////////////////////////
// Platform Detection and Memory Allocation
///////////////////////////////////////////////////////////////////////////////

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

version (all)
{
    import core.stdc.stdint : uintptr_t; // for _beginthreadex decl below
    import core.stdc.stdlib;             // for malloc, atexit
    import core.sys.windows.basetsd /+: HANDLE+/;
    import core.sys.windows.threadaux : getThreadStackBottom, impersonate_thread, OpenThreadHandle;
    import core.sys.windows.winbase /+: CloseHandle, CREATE_SUSPENDED, DuplicateHandle, GetCurrentThread,
        GetCurrentThreadId, GetCurrentProcess, GetExitCodeThread, GetSystemInfo, GetThreadContext,
        GetThreadPriority, INFINITE, ResumeThread, SetThreadPriority, Sleep,  STILL_ACTIVE,
        SuspendThread, SwitchToThread, SYSTEM_INFO, THREAD_PRIORITY_IDLE, THREAD_PRIORITY_NORMAL,
        THREAD_PRIORITY_TIME_CRITICAL, WAIT_OBJECT_0, WaitForSingleObject+/;
    import core.sys.windows.windef /+: TRUE+/;
    import core.sys.windows.winnt /+: CONTEXT, CONTEXT_CONTROL, CONTEXT_INTEGER+/;

    private extern (Windows) alias btex_fptr = uint function(void*);
    private extern (C) uintptr_t _beginthreadex(void*, uint, btex_fptr, void*, uint, uint*) nothrow @nogc;
}

version (GNU)
{
    import gcc.builtins;
}

/**
 * Hook for whatever EH implementation is used to save/restore some data
 * per stack.
 *
 * Params:
 *     newContext = The return value of the prior call to this function
 *         where the stack was last swapped out, or null when a fiber stack
 *         is switched in for the first time.
 */
private extern(C) void* _d_eh_swapContext(void* newContext) nothrow @nogc;

// LDC: changed from `version (DigitalMars)`
version (all)
{
    // LDC: changed from `version (Windows)`
    version (CRuntime_Microsoft)
    {
        extern(D) void* swapContext(void* newContext) nothrow @nogc
        {
            return _d_eh_swapContext(newContext);
        }
    }
    else
    {
        extern(C) void* _d_eh_swapContextDwarf(void* newContext) nothrow @nogc;

        extern(D) void* swapContext(void* newContext) nothrow @nogc
        {
            /* Detect at runtime which scheme is being used.
             * Eventually, determine it statically.
             */
            static int which = 0;
            final switch (which)
            {
                case 0:
                {
                    assert(newContext == null);
                    auto p = _d_eh_swapContext(newContext);
                    auto pdwarf = _d_eh_swapContextDwarf(newContext);
                    if (p)
                    {
                        which = 1;
                        return p;
                    }
                    else if (pdwarf)
                    {
                        which = 2;
                        return pdwarf;
                    }
                    return null;
                }
                case 1:
                    return _d_eh_swapContext(newContext);
                case 2:
                    return _d_eh_swapContextDwarf(newContext);
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////
// Thread
///////////////////////////////////////////////////////////////////////////////

/**
 * This class encapsulates all threading functionality for the D
 * programming language.  As thread manipulation is a required facility
 * for garbage collection, all user threads should derive from this
 * class, and instances of this class should never be explicitly deleted.
 * A new thread may be created using either derivation or composition, as
 * in the following example.
 */
class Thread : ThreadBase
{
    //
    // Standard thread data
    //
    version (all)
    {
        private HANDLE          m_hndl;
    }

    //
    // Standard types
    //
    version (Windows)
    {
        alias TLSKey = uint;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Initialization
    ///////////////////////////////////////////////////////////////////////////


    /**
     * Initializes a thread object which is associated with a static
     * D function.
     *
     * Params:
     *  fn = The thread function.
     *  sz = The stack size for this thread.
     *
     * In:
     *  fn must not be null.
     */
    this( void function() fn, size_t sz = 0 ) @safe pure nothrow @nogc
    {
        super(fn, sz);
    }


    /**
     * Initializes a thread object which is associated with a dynamic
     * D function.
     *
     * Params:
     *  dg = The thread function.
     *  sz = The stack size for this thread.
     *
     * In:
     *  dg must not be null.
     */
    this( void delegate() dg, size_t sz = 0 ) @safe pure nothrow @nogc
    {
        super(dg, sz);
    }

    package this( size_t sz = 0 ) @safe pure nothrow @nogc
    {
        super(sz);
    }

    /**
     * Cleans up any remaining resources used by this object.
     */
    ~this() nothrow @nogc
    {
        if (super.destructBeforeDtor())
            return;

        version (Windows)
        {
            m_addr = m_addr.init;
            CloseHandle( m_hndl );
            m_hndl = m_hndl.init;
        }
    }

    //
    // Thread entry point.  Invokes the function or delegate passed on
    // construction (if any).
    //
    private final void run()
    {
        super.run();
    }

    /**
     * Provides a reference to the calling thread.
     *
     * Returns:
     *  The thread object representing the calling thread.  The result of
     *  deleting this object is undefined.  If the current thread is not
     *  attached to the runtime, a null reference is returned.
     */
    static Thread getThis() @safe nothrow @nogc
    {
        return ThreadBase.getThis().toThread;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Thread Context and GC Scanning Support
    ///////////////////////////////////////////////////////////////////////////


    version (Windows)
    {
        version (X86)
        {
            uint[8]         m_reg; // edi,esi,ebp,esp,ebx,edx,ecx,eax
        }
        else version (X86_64)
        {
            ulong[16]       m_reg; // rdi,rsi,rbp,rsp,rbx,rdx,rcx,rax
                                   // r8,r9,r10,r11,r12,r13,r14,r15
        }
        else
        {
            static assert(false, "Architecture not supported." );
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    // General Actions
    ///////////////////////////////////////////////////////////////////////////


    /**
     * Starts the thread and invokes the function or delegate passed upon
     * construction.
     *
     * In:
     *  This routine may only be called once per thread instance.
     *
     * Throws:
     *  ThreadException if the thread fails to start.
     */
    final Thread start() nothrow
    in
    {
        assert( !next && !prev );
    }
    do
    {
        auto wasThreaded  = multiThreadedFlag;
        multiThreadedFlag = true;
        scope( failure )
        {
            if ( !wasThreaded )
                multiThreadedFlag = false;
        }

        version (Shared)
        {
            auto ps = cast(void**).malloc(2 * size_t.sizeof);
            if (ps is null) onOutOfMemoryError();
        }

        version (all)
        {
            // NOTE: If a thread is just executing DllMain()
            //       while another thread is started here, it holds an OS internal
            //       lock that serializes DllMain with CreateThread. As the code
            //       might request a synchronization on slock (e.g. in thread_findByAddr()),
            //       we cannot hold that lock while creating the thread without
            //       creating a deadlock
            //
            // Solution: Create the thread in suspended state and then
            //       add and resume it with slock acquired
            assert(m_sz <= uint.max, "m_sz must be less than or equal to uint.max");
            version (Shared)
                auto threadArg = cast(void*) ps;
            else
                auto threadArg = cast(void*) this;
            m_hndl = cast(HANDLE) _beginthreadex( null, cast(uint) m_sz, &thread_entryPoint, threadArg, CREATE_SUSPENDED, &m_addr );
            if ( cast(size_t) m_hndl == 0 )
                onThreadError( "Error creating thread" );
        }

        slock.lock_nothrow();
        scope(exit) slock.unlock_nothrow();
        {
            incrementAboutToStart(this);

            version (Shared)
            {
                auto libs = externDFunc!("rt.sections_elf_shared.pinLoadedLibraries",
                                         void* function() @nogc nothrow)();

                ps[0] = cast(void*)this;
                ps[1] = cast(void*)libs;

                version (all)
                {
                    if ( ResumeThread( m_hndl ) == -1 )
                    {
                        externDFunc!("rt.sections_elf_shared.unpinLoadedLibraries",
                                     void function(void*) @nogc nothrow)(libs);
                        .free(ps);
                        onThreadError( "Error resuming thread" );
                    }
                }
            }
            else
            {
                version (all)
                {
                    if ( ResumeThread( m_hndl ) == -1 )
                        onThreadError( "Error resuming thread" );
                }
            }

            return this;
        }
    }

    /**
     * Waits for this thread to complete.  If the thread terminated as the
     * result of an unhandled exception, this exception will be rethrown.
     *
     * Params:
     *  rethrow = Rethrow any unhandled exception which may have caused this
     *            thread to terminate.
     *
     * Throws:
     *  ThreadException if the operation fails.
     *  Any exception not handled by the joined thread.
     *
     * Returns:
     *  Any exception not handled by this thread if rethrow = false, null
     *  otherwise.
     */
    override final Throwable join( bool rethrow = true )
    {
        version (Windows)
        {
            if ( m_addr != m_addr.init && WaitForSingleObject( m_hndl, INFINITE ) != WAIT_OBJECT_0 )
                throw new ThreadException( "Unable to join thread" );
            // NOTE: m_addr must be cleared before m_hndl is closed to avoid
            //       a race condition with isRunning. The operation is done
            //       with atomicStore to prevent compiler reordering.
            atomicStore!(MemoryOrder.raw)(*cast(shared)&m_addr, m_addr.init);
            CloseHandle( m_hndl );
            m_hndl = m_hndl.init;
        }

        if ( m_unhandled )
        {
            if ( rethrow )
                throw m_unhandled;
            return m_unhandled;
        }
        return null;
    }


    ///////////////////////////////////////////////////////////////////////////
    // Thread Priority Actions
    ///////////////////////////////////////////////////////////////////////////

    version (Windows)
    {
        @property static int PRIORITY_MIN() @nogc nothrow pure @safe
        {
            return THREAD_PRIORITY_IDLE;
        }

        @property static const(int) PRIORITY_MAX() @nogc nothrow pure @safe
        {
            return THREAD_PRIORITY_TIME_CRITICAL;
        }

        @property static int PRIORITY_DEFAULT() @nogc nothrow pure @safe
        {
            return THREAD_PRIORITY_NORMAL;
        }
    }

    /**
     * Gets the scheduling priority for the associated thread.
     *
     * Note: Getting the priority of a thread that already terminated
     * might return the default priority.
     *
     * Returns:
     *  The scheduling priority of this thread.
     */
    final @property int priority()
    {
        version (all)
        {
            return GetThreadPriority( m_hndl );
        }
    }


    /**
     * Sets the scheduling priority for the associated thread.
     *
     * Note: Setting the priority of a thread that already terminated
     * might have no effect.
     *
     * Params:
     *  val = The new scheduling priority of this thread.
     */
    final @property void priority( int val )
    in
    {
        assert(val >= PRIORITY_MIN);
        assert(val <= PRIORITY_MAX);
    }
    do
    {
        version (all)
        {
            if ( !SetThreadPriority( m_hndl, val ) )
                throw new ThreadException( "Unable to set thread priority" );
        }
    }

    /**
     * Tests whether this thread is running.
     *
     * Returns:
     *  true if the thread is running, false if not.
     */
    override final @property bool isRunning() nothrow @nogc
    {
        if (!super.isRunning())
            return false;

        version (Windows)
        {
            uint ecode = 0;
            GetExitCodeThread( m_hndl, &ecode );
            return ecode == STILL_ACTIVE;
        }
        else version (Posix)
        {
            return atomicLoad(m_isRunning);
        }
    }


    ///////////////////////////////////////////////////////////////////////////
    // Actions on Calling Thread
    ///////////////////////////////////////////////////////////////////////////


    /**
     * Suspends the calling thread for at least the supplied period.  This may
     * result in multiple OS calls if period is greater than the maximum sleep
     * duration supported by the operating system.
     *
     * Params:
     *  val = The minimum duration the calling thread should be suspended.
     *
     * In:
     *  period must be non-negative.
     *
     * Example:
     * ------------------------------------------------------------------------
     *
     * Thread.sleep( dur!("msecs")( 50 ) );  // sleep for 50 milliseconds
     * Thread.sleep( dur!("seconds")( 5 ) ); // sleep for 5 seconds
     *
     * ------------------------------------------------------------------------
     */
    static void sleep( Duration val ) @nogc nothrow @trusted
    in
    {
        assert( !val.isNegative );
    }
    do
    {
        version (Windows)
        {
            auto maxSleepMillis = dur!("msecs")( uint.max - 1 );

            // avoid a non-zero time to be round down to 0
            if ( val > dur!"msecs"( 0 ) && val < dur!"msecs"( 1 ) )
                val = dur!"msecs"( 1 );

            // NOTE: In instances where all other threads in the process have a
            //       lower priority than the current thread, the current thread
            //       will not yield with a sleep time of zero.  However, unlike
            //       yield(), the user is not asking for a yield to occur but
            //       only for execution to suspend for the requested interval.
            //       Therefore, expected performance may not be met if a yield
            //       is forced upon the user.
            while ( val > maxSleepMillis )
            {
                Sleep( cast(uint)
                       maxSleepMillis.total!"msecs" );
                val -= maxSleepMillis;
            }
            Sleep( cast(uint) val.total!"msecs" );
        }
        else version (Posix)
        {
            timespec tin  = void;
            timespec tout = void;

            val.split!("seconds", "nsecs")(tin.tv_sec, tin.tv_nsec);
            if ( val.total!"seconds" > tin.tv_sec.max )
                tin.tv_sec  = tin.tv_sec.max;
            while ( true )
            {
                if ( !nanosleep( &tin, &tout ) )
                    return;
                if ( errno != EINTR )
                    assert(0, "Unable to sleep for the specified duration");
                tin = tout;
            }
        }
    }


    /**
     * Forces a context switch to occur away from the calling thread.
     */
    static void yield() @nogc nothrow
    {
        version (Windows)
            SwitchToThread();
        else version (Posix)
            sched_yield();
    }
}

private Thread toThread(return scope ThreadBase t) @trusted nothrow @nogc pure
{
    return cast(Thread) cast(void*) t;
}

private extern(D) static void thread_yield() @nogc nothrow
{
    Thread.yield();
}

///////////////////////////////////////////////////////////////////////////////
// GC Support Routines
///////////////////////////////////////////////////////////////////////////////

private extern (D) ThreadBase attachThread(ThreadBase _thisThread) @nogc nothrow
{
    Thread thisThread = _thisThread.toThread();

    StackContext* thisContext = &thisThread.m_main;
    assert( thisContext == thisThread.m_curr );

    version (SupportSanitizers)
    {
        // Save this thread's fake stack handler, to be stored in each StackContext belonging to this thread.
        thisThread.asan_fakestack  = asanGetCurrentFakeStack();
        thisContext.asan_fakestack = thisThread.asan_fakestack;
    }

    version (Windows)
    {
        thisThread.m_addr  = GetCurrentThreadId();
        thisThread.m_hndl  = GetCurrentThreadHandle();
        thisContext.bstack = getStackBottom();
        thisContext.tstack = thisContext.bstack;
    }

    thisThread.m_isDaemon = true;
    thisThread.tlsGCdataInit();
    Thread.setThis( thisThread );

    Thread.add( thisThread, false );
    Thread.add( thisContext );
    if ( Thread.sm_main !is null )
        multiThreadedFlag = true;
    return thisThread;
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


version (all)
{
    // NOTE: These calls are not safe on Posix systems that use signals to
    //       perform garbage collection.  The suspendHandler uses getThis()
    //       to get the thread handle so getThis() must be a simple call.
    //       Mutexes can't safely be acquired inside signal handlers, and
    //       even if they could, the mutex needed (Thread.slock) is held by
    //       thread_suspendAll().  So in short, these routines will remain
    //       Windows-specific.  If they are truly needed elsewhere, the
    //       suspendHandler will need a way to call a version of getThis()
    //       that only does the TLS lookup without the fancy fallback stuff.

    /// ditto
    extern (C) Thread thread_attachByAddr( ThreadID addr )
    {
        return thread_attachByAddrB( addr, getThreadStackBottom( addr ) );
    }


    /// ditto
    extern (C) Thread thread_attachByAddrB( ThreadID addr, void* bstack )
    {
        GC.disable(); scope(exit) GC.enable();

        if (auto t = thread_findByAddr(addr).toThread)
            return t;

        Thread        thisThread  = new Thread();
        StackContext* thisContext = &thisThread.m_main;
        assert( thisContext == thisThread.m_curr );

        thisThread.m_addr  = addr;
        thisContext.bstack = bstack;
        thisContext.tstack = thisContext.bstack;

        thisThread.m_isDaemon = true;

        if ( addr == GetCurrentThreadId() )
        {
            thisThread.m_hndl = GetCurrentThreadHandle();
            thisThread.tlsGCdataInit();
            Thread.setThis( thisThread );

            version (SupportSanitizers)
            {
                // Save this thread's fake stack handler, to be stored in each StackContext belonging to this thread.
                thisThread.asan_fakestack  = asanGetCurrentFakeStack();
            }
        }
        else
        {
            thisThread.m_hndl = OpenThreadHandle( addr );
            impersonate_thread(addr,
            {
                thisThread.tlsGCdataInit();
                Thread.setThis( thisThread );

                version (SupportSanitizers)
                {
                    // Save this thread's fake stack handler, to be stored in each StackContext belonging to this thread.
                    thisThread.asan_fakestack  = asanGetCurrentFakeStack();
                }
            });
        }

        version (SupportSanitizers)
        {
            thisContext.asan_fakestack = thisThread.asan_fakestack;
        }

        Thread.add( thisThread, false );
        Thread.add( thisContext );
        if ( Thread.sm_main !is null )
            multiThreadedFlag = true;
        return thisThread;
    }
}

version (LDC) {} else
version (PPC64) version = ExternStackShell;

private extern (D) void scanWindowsOnly(scope ScanAllThreadsTypeFn scan, ThreadBase _t) nothrow
{
    auto t = _t.toThread;

    scan( ScanType.stack, t.m_reg.ptr, t.m_reg.ptr + t.m_reg.length );
}


/**
 * Returns the process ID of the calling process, which is guaranteed to be
 * unique on the system. This call is always successful.
 *
 * Example:
 * ---
 * writefln("Current process id: %s", getpid());
 * ---
 */
version (all)
{
    alias getpid = core.sys.windows.winbase.GetCurrentProcessId;
}

version (LDC_Windows)
{
    private extern(D) void* getStackBottom() nothrow @nogc @naked
    {
        version (X86)
            return __asm!(void*)("mov %fs:(4), $0", "=r");
        else version (X86_64)
            return __asm!(void*)("mov %gs:0($1), $0", "=r,r", 8);
        else
            static assert(false, "Architecture not supported.");
    }
}
else
private extern(D) void* getStackBottom() nothrow @nogc
{
    version (Windows)
    {
        version (D_InlineAsm_X86)
            asm pure nothrow @nogc { naked; mov EAX, FS:4; ret; }
        else version (D_InlineAsm_X86_64)
            asm pure nothrow @nogc
            {    naked;
                 mov RAX, 8;
                 mov RAX, GS:[RAX];
                 ret;
            }
        else
            static assert(false, "Architecture not supported.");
    }
    else
        static assert(false, "Platform not supported.");
}

/**
 * Suspend the specified thread and load stack and register information for
 * use by thread_scanAll.  If the supplied thread is the calling thread,
 * stack and register information will be loaded but the thread will not
 * be suspended.  If the suspend operation fails and the thread is not
 * running then it will be removed from the global thread list, otherwise
 * an exception will be thrown.
 *
 * Params:
 *  t = The thread to suspend.
 *
 * Throws:
 *  ThreadError if the suspend operation fails for a running thread.
 * Returns:
 *  Whether the thread is now suspended (true) or terminated (false).
 */
private extern (D) bool suspend( Thread t ) nothrow @nogc
{
    Duration waittime = dur!"usecs"(10);
 Lagain:
    if (!t.isRunning)
    {
        Thread.remove(t);
        return false;
    }
    else if (t.m_isInCriticalRegion)
    {
        ThreadBase.criticalRegionLock.unlock_nothrow();
        Thread.sleep(waittime);
        if (waittime < dur!"msecs"(10)) waittime *= 2;
        ThreadBase.criticalRegionLock.lock_nothrow();
        goto Lagain;
    }

    version (Windows)
    {
        if ( t.m_addr != GetCurrentThreadId() && SuspendThread( t.m_hndl ) == 0xFFFFFFFF )
        {
            if ( !t.isRunning )
            {
                Thread.remove( t );
                return false;
            }
            onThreadError( "Unable to suspend thread" );
        }

        CONTEXT context = void;
        context.ContextFlags = CONTEXT_INTEGER | CONTEXT_CONTROL;

        if ( !GetThreadContext( t.m_hndl, &context ) )
            onThreadError( "Unable to load thread context" );
        version (X86)
        {
            if ( !t.m_lock )
                t.m_curr.tstack = cast(void*) context.Esp;
            // eax,ebx,ecx,edx,edi,esi,ebp,esp
            t.m_reg[0] = context.Eax;
            t.m_reg[1] = context.Ebx;
            t.m_reg[2] = context.Ecx;
            t.m_reg[3] = context.Edx;
            t.m_reg[4] = context.Edi;
            t.m_reg[5] = context.Esi;
            t.m_reg[6] = context.Ebp;
            t.m_reg[7] = context.Esp;
        }
        else version (X86_64)
        {
            if ( !t.m_lock )
                t.m_curr.tstack = cast(void*) context.Rsp;
            // rax,rbx,rcx,rdx,rdi,rsi,rbp,rsp
            t.m_reg[0] = context.Rax;
            t.m_reg[1] = context.Rbx;
            t.m_reg[2] = context.Rcx;
            t.m_reg[3] = context.Rdx;
            t.m_reg[4] = context.Rdi;
            t.m_reg[5] = context.Rsi;
            t.m_reg[6] = context.Rbp;
            t.m_reg[7] = context.Rsp;
            // r8,r9,r10,r11,r12,r13,r14,r15
            t.m_reg[8]  = context.R8;
            t.m_reg[9]  = context.R9;
            t.m_reg[10] = context.R10;
            t.m_reg[11] = context.R11;
            t.m_reg[12] = context.R12;
            t.m_reg[13] = context.R13;
            t.m_reg[14] = context.R14;
            t.m_reg[15] = context.R15;
        }
        else
        {
            static assert(false, "Architecture not supported." );
        }
    }

    return true;
}

/**
 * Suspend all threads but the calling thread for "stop the world" garbage
 * collection runs.  This function may be called multiple times, and must
 * be followed by a matching number of calls to thread_resumeAll before
 * processing is resumed.
 *
 * Throws:
 *  ThreadError if the suspend operation fails for a running thread.
 */
extern (C) void thread_suspendAll() nothrow
{
    // NOTE: We've got an odd chicken & egg problem here, because while the GC
    //       is required to call thread_init before calling any other thread
    //       routines, thread_init may allocate memory which could in turn
    //       trigger a collection.  Thus, thread_suspendAll, thread_scanAll,
    //       and thread_resumeAll must be callable before thread_init
    //       completes, with the assumption that no other GC memory has yet
    //       been allocated by the system, and thus there is no risk of losing
    //       data if the global thread list is empty.  The check of
    //       Thread.sm_tbeg below is done to ensure thread_init has completed,
    //       and therefore that calling Thread.getThis will not result in an
    //       error.  For the short time when Thread.sm_tbeg is null, there is
    //       no reason not to simply call the multithreaded code below, with
    //       the expectation that the foreach loop will never be entered.
    if ( !multiThreadedFlag && Thread.sm_tbeg )
    {
        if ( ++suspendDepth == 1 )
            suspend( Thread.getThis() );

        return;
    }

    Thread.slock.lock_nothrow();
    {
        if ( ++suspendDepth > 1 )
            return;

        Thread.criticalRegionLock.lock_nothrow();
        scope (exit) Thread.criticalRegionLock.unlock_nothrow();
        size_t cnt;
        bool suspendedSelf;
        Thread t = ThreadBase.sm_tbeg.toThread;
        while (t)
        {
            auto tn = t.next.toThread;
            if (suspend(t))
            {
                if (t is ThreadBase.getThis())
                    suspendedSelf = true;
                ++cnt;
            }
            t = tn;
        }
    }
}

/**
 * Resume the specified thread and unload stack and register information.
 * If the supplied thread is the calling thread, stack and register
 * information will be unloaded but the thread will not be resumed.  If
 * the resume operation fails and the thread is not running then it will
 * be removed from the global thread list, otherwise an exception will be
 * thrown.
 *
 * Params:
 *  t = The thread to resume.
 *
 * Throws:
 *  ThreadError if the resume fails for a running thread.
 */
private extern (D) void resume(ThreadBase _t) nothrow @nogc
{
    Thread t = _t.toThread;

    version (all)
    {
        if ( t.m_addr != GetCurrentThreadId() && ResumeThread( t.m_hndl ) == 0xFFFFFFFF )
        {
            if ( !t.isRunning )
            {
                Thread.remove( t );
                return;
            }
            onThreadError( "Unable to resume thread" );
        }

        if ( !t.m_lock )
            t.m_curr.tstack = t.m_curr.bstack;
        t.m_reg[0 .. $] = 0;
    }
}


/**
 * Initializes the thread module.  This function must be called by the
 * garbage collector on startup and before any other thread routines
 * are called.
 */
extern (C) void thread_init() @nogc nothrow
{
    // NOTE: If thread_init itself performs any allocations then the thread
    //       routines reserved for garbage collector use may be called while
    //       thread_init is being processed.  However, since no memory should
    //       exist to be scanned at this point, it is sufficient for these
    //       functions to detect the condition and return immediately.

    initLowlevelThreads();
    Thread.initLocks();

    _mainThreadStore[] = __traits(initSymbol, Thread)[];
    Thread.sm_main = attachThread((cast(Thread)_mainThreadStore.ptr).__ctor());
}

private alias MainThreadStore = void[__traits(classInstanceSize, Thread)];
/*TODO: change to package:*/
public  __gshared align(__traits(classInstanceAlignment, Thread)) MainThreadStore _mainThreadStore;

/**
 * Terminates the thread module. No other thread routine may be called
 * afterwards.
 */
extern (C) void thread_term() @nogc nothrow
{
    thread_term_tpl!(Thread)(_mainThreadStore);
}


///////////////////////////////////////////////////////////////////////////////
// Thread Entry Point and Signal Handlers
///////////////////////////////////////////////////////////////////////////////

version (all)
{
    private
    {
        //
        // Entry point for Windows threads
        //
        extern (Windows) uint thread_entryPoint( void* arg ) nothrow
        {
            version (Shared)
            {
                Thread obj = cast(Thread)(cast(void**)arg)[0];
                auto loadedLibraries = (cast(void**)arg)[1];
                .free(arg);
            }
            else
            {
                Thread obj = cast(Thread)arg;
            }
            assert( obj );

            // loadedLibraries need to be inherited from parent thread
            // before initilizing GC for TLS (rt_tlsgc_init)
            version (Shared)
            {
                externDFunc!("rt.sections_elf_shared.inheritLoadedLibraries",
                             void function(void*) @nogc nothrow)(loadedLibraries);
            }

            obj.initDataStorage();

            Thread.setThis(obj);
            Thread.add(obj);
            scope (exit)
            {
                Thread.remove(obj);
                obj.destroyDataStorage();
            }
            Thread.add(&obj.m_main);

            // NOTE: No GC allocations may occur until the stack pointers have
            //       been set and Thread.getThis returns a valid reference to
            //       this thread object (this latter condition is not strictly
            //       necessary on Windows but it should be followed for the
            //       sake of consistency).

            // TODO: Consider putting an auto exception object here (using
            //       alloca) forOutOfMemoryError plus something to track
            //       whether an exception is in-flight?

            void append( Throwable t )
            {
                obj.m_unhandled = Throwable.chainTogether(obj.m_unhandled, t);
            }

            version (D_InlineAsm_X86)
            {
                asm nothrow @nogc { fninit; }
            }

            try
            {
                rt_moduleTlsCtor();
                try
                {
                    obj.run();
                }
                catch ( Throwable t )
                {
                    append( t );
                }
                rt_moduleTlsDtor();
                version (Shared)
                {
                    externDFunc!("rt.sections_elf_shared.cleanupLoadedLibraries",
                                 void function() @nogc nothrow)();
                }
            }
            catch ( Throwable t )
            {
                append( t );
            }
            return 0;
        }


        HANDLE GetCurrentThreadHandle() nothrow @nogc
        {
            const uint DUPLICATE_SAME_ACCESS = 0x00000002;

            HANDLE curr = GetCurrentThread(),
                   proc = GetCurrentProcess(),
                   hndl;

            DuplicateHandle( proc, curr, proc, &hndl, 0, TRUE, DUPLICATE_SAME_ACCESS );
            return hndl;
        }
    }
}

///////////////////////////////////////////////////////////////////////////////
// lowlovel threading support
///////////////////////////////////////////////////////////////////////////////

private
{
    version (all):
    // If the runtime is dynamically loaded as a DLL, there is a problem with
    // threads still running when the DLL is supposed to be unloaded:
    //
    // - with the VC runtime starting with VS2015 (i.e. using the Universal CRT)
    //   a thread created with _beginthreadex increments the DLL reference count
    //   and decrements it when done, so that the DLL is no longer unloaded unless
    //   all the threads have terminated. With the DLL reference count held up
    //   by a thread that is only stopped by a signal from a static destructor or
    //   the termination of the runtime will cause the DLL to never be unloaded.
    //
    // - with the DigitalMars runtime and VC runtime up to VS2013, the thread
    //   continues to run, but crashes once the DLL is unloaded from memory as
    //   the code memory is no longer accessible. Stopping the threads is not possible
    //   from within the runtime termination as it is invoked from
    //   DllMain(DLL_PROCESS_DETACH) holding a lock that prevents threads from
    //   terminating.
    //
    // Solution: start a watchdog thread that keeps the DLL reference count above 0 and
    // checks it periodically. If it is equal to 1 (plus the number of started threads), no
    // external references to the DLL exist anymore, threads can be stopped
    // and runtime termination and DLL unload can be invoked via FreeLibraryAndExitThread.
    // Note: runtime termination is then performed by a different thread than at startup.
    //
    // Note: if the DLL is never unloaded, process termination kills all threads
    // and signals their handles before unconditionally calling DllMain(DLL_PROCESS_DETACH).

    import core.sys.windows.winbase : FreeLibraryAndExitThread, GetModuleHandleExW,
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
    import core.sys.windows.windef : HMODULE;
    import core.sys.windows.dll : dll_getRefCount;

    version (CRuntime_Microsoft)
        extern(C) extern __gshared ubyte msvcUsesUCRT; // from rt/msvc.d

    /// set during termination of a DLL on Windows, i.e. while executing DllMain(DLL_PROCESS_DETACH)
    public __gshared bool thread_DLLProcessDetaching;

    __gshared HMODULE ll_dllModule;
    __gshared ThreadID ll_dllMonitorThread;

    int ll_countLowLevelThreadsWithDLLUnloadCallback() nothrow
    {
        lowlevelLock.lock_nothrow();
        scope(exit) lowlevelLock.unlock_nothrow();

        int cnt = 0;
        foreach (i; 0 .. ll_nThreads)
            if (ll_pThreads[i].cbDllUnload)
                cnt++;
        return cnt;
    }

    bool ll_dllHasExternalReferences() nothrow
    {
        version (CRuntime_DigitalMars)
            enum internalReferences = 1; // only the watchdog thread
        else
            int internalReferences =  msvcUsesUCRT ? 1 + ll_countLowLevelThreadsWithDLLUnloadCallback() : 1;

        int refcnt = dll_getRefCount(ll_dllModule);
        return refcnt > internalReferences;
    }

    private void monitorDLLRefCnt() nothrow
    {
        // this thread keeps the DLL alive until all external references are gone
        while (ll_dllHasExternalReferences())
        {
            Thread.sleep(100.msecs);
        }

        // the current thread will be terminated below
        ll_removeThread(GetCurrentThreadId());

        for (;;)
        {
            ThreadID tid;
            void delegate() nothrow cbDllUnload;
            {
                lowlevelLock.lock_nothrow();
                scope(exit) lowlevelLock.unlock_nothrow();

                foreach (i; 0 .. ll_nThreads)
                    if (ll_pThreads[i].cbDllUnload)
                    {
                        cbDllUnload = ll_pThreads[i].cbDllUnload;
                        tid = ll_pThreads[0].tid;
                    }
            }
            if (!cbDllUnload)
                break;
            cbDllUnload();
            assert(!findLowLevelThread(tid));
        }

        FreeLibraryAndExitThread(ll_dllModule, 0);
    }

    int ll_getDLLRefCount() nothrow @nogc
    {
        if (!ll_dllModule &&
            !GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                cast(const(wchar)*) &ll_getDLLRefCount, &ll_dllModule))
            return -1;
        return dll_getRefCount(ll_dllModule);
    }

    bool ll_startDLLUnloadThread() nothrow @nogc
    {
        int refcnt = ll_getDLLRefCount();
        if (refcnt < 0)
            return false; // not a dynamically loaded DLL

        if (ll_dllMonitorThread !is ThreadID.init)
            return true;

        // if a thread is created from a DLL, the MS runtime (starting with VC2015) increments the DLL reference count
        // to avoid the DLL being unloaded while the thread is still running. Mimick this behavior here for all
        // runtimes not doing this
        version (CRuntime_DigitalMars)
            enum needRef = true;
        else
            bool needRef = !msvcUsesUCRT;

        if (needRef)
        {
            HMODULE hmod;
            GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, cast(const(wchar)*) &ll_getDLLRefCount, &hmod);
        }

        ll_dllMonitorThread = createLowLevelThread(() { monitorDLLRefCnt(); });
        return ll_dllMonitorThread != ThreadID.init;
    }
}

/**
 * Create a thread not under control of the runtime, i.e. TLS module constructors are
 * not run and the GC does not suspend it during a collection.
 *
 * Params:
 *  dg        = delegate to execute in the created thread.
 *  stacksize = size of the stack of the created thread. The default of 0 will select the
 *              platform-specific default size.
 *  cbDllUnload = Windows only: if running in a dynamically loaded DLL, this delegate will be called
 *              if the DLL is supposed to be unloaded, but the thread is still running.
 *              The thread must be terminated via `joinLowLevelThread` by the callback.
 *
 * Returns: the platform specific thread ID of the new thread. If an error occurs, `ThreadID.init`
 *  is returned.
 */
ThreadID createLowLevelThread(void delegate() nothrow dg, uint stacksize = 0,
                              void delegate() nothrow cbDllUnload = null) nothrow @nogc
{
    void delegate() nothrow* context = cast(void delegate() nothrow*)malloc(dg.sizeof);
    *context = dg;

    ThreadID tid;
    version (all)
    {
        // the thread won't start until after the DLL is unloaded
        if (thread_DLLProcessDetaching)
            return ThreadID.init;

        static extern (Windows) uint thread_lowlevelEntry(void* ctx) nothrow
        {
            auto dg = *cast(void delegate() nothrow*)ctx;
            free(ctx);

            dg();
            ll_removeThread(GetCurrentThreadId());
            return 0;
        }

        // see Thread.start() for why thread is created in suspended state
        HANDLE hThread = cast(HANDLE) _beginthreadex(null, stacksize, &thread_lowlevelEntry,
                                                     context, CREATE_SUSPENDED, &tid);
        if (!hThread)
            return ThreadID.init;
    }

    lowlevelLock.lock_nothrow();
    scope(exit) lowlevelLock.unlock_nothrow();

    ll_nThreads++;
    ll_pThreads = cast(ll_ThreadData*)realloc(ll_pThreads, ll_ThreadData.sizeof * ll_nThreads);

    version (all)
    {
        ll_pThreads[ll_nThreads - 1].tid = tid;
        ll_pThreads[ll_nThreads - 1].cbDllUnload = cbDllUnload;
        if (ResumeThread(hThread) == -1)
            onThreadError("Error resuming thread");
        CloseHandle(hThread);

        if (cbDllUnload)
            ll_startDLLUnloadThread();
    }

    return tid;
}

/**
 * Wait for a thread created with `createLowLevelThread` to terminate.
 *
 * Note: In a Windows DLL, if this function is called via DllMain with
 *       argument DLL_PROCESS_DETACH, the thread is terminated forcefully
 *       without proper cleanup as a deadlock would happen otherwise.
 *
 * Params:
 *  tid = the thread ID returned by `createLowLevelThread`.
 */
version (DruntimeAbstractRt)
    public import external.core.thread : joinLowLevelThread;
else
void joinLowLevelThread(ThreadID tid) nothrow @nogc
{
    version (all)
    {
        HANDLE handle = OpenThreadHandle(tid);
        if (!handle)
            return;

        if (thread_DLLProcessDetaching)
        {
            // When being called from DllMain/DLL_DETACH_PROCESS, threads cannot stop
            //  due to the loader lock being held by the current thread.
            // On the other hand, the thread must not continue to run as it will crash
            //  if the DLL is unloaded. The best guess is to terminate it immediately.
            TerminateThread(handle, 1);
            WaitForSingleObject(handle, 10); // give it some time to terminate, but don't wait indefinitely
        }
        else
            WaitForSingleObject(handle, INFINITE);
        CloseHandle(handle);
    }
}
