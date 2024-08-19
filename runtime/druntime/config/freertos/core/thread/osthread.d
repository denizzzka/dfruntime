/**
 * The osthread module provides low-level, OS-dependent code
 * for thread creation and management.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/core/thread/osthread.d)
 */

module core.thread.osthread;

import core.internal.spinlock: SpinLock;
import rt.minfo: rt_moduleTlsCtor, rt_moduleTlsDtor;
import core.stdc.stdlib: malloc, aligned_alloc, realloc, free;
import core.sync.event_awaiter: EventAwaiter;
import core.time: Duration, dur;
import core.thread.context: StackContext;
import core.thread.threadbase;
import core.thread.types;
static import os = internal.binding /*freertos_binding*/;

enum DefaultTaskPriority = 3;
enum DefaultStackSize = 2048 * os.StackType_t.sizeof;

private struct TaskProperties
{
    os.StaticTask_t tcb;
    EventAwaiter joinEvent;
    void* stackBuff;
}

extern(C) void thread_entryPoint(void* arg) nothrow
in(arg)
{
    auto obj = cast(Thread) arg;

    scope(exit)
    {
        obj.isRunning = false;
        obj.taskProperties.joinEvent.set();
        os.vTaskDelete(null);
    }

    obj.initDataStorage();

    Thread.setThis(obj);

    ThreadBase.add(obj);
    scope(exit) ThreadBase.remove(obj);

    Thread.add(&obj.m_main);

    void append(Throwable t)
    {
        obj.m_unhandled = Throwable.chainTogether(obj.m_unhandled, t);
    }

    try
    {
        rt_moduleTlsCtor();

        try
            obj.run();
        catch (Throwable t)
            append( t );

        rt_moduleTlsDtor();
    }
    catch (Throwable t)
        append( t );
}

size_t getpid() nothrow @nogc
{
    return cast(size_t) getThreadID();
}

private ThreadID getThreadID() nothrow @nogc
{
    return os.xTaskGetCurrentTaskHandle();
}

private extern(C) void* _d_eh_swapContext(void* newContext) nothrow @nogc;

void* swapContext(void* newContext) nothrow @nogc
{
    return _d_eh_swapContext(newContext);
}

struct LowLevelThreadSystemParams
{
    const(char*) name = "D low-level";
}

alias LLThreadDg = void delegate() nothrow;

private struct LLTaskProperties
{
    LLThreadDg dg;
}

ThreadID createLowLevelThread(
    LLThreadDg dg, uint stacksize = 0,
    LLThreadDg cbDllUnload = null, //TODO: propose to remove this arg in upstream?
    LowLevelThreadSystemParams params = LowLevelThreadSystemParams.init
) nothrow @nogc
in(stacksize % os.StackType_t.sizeof == 0)
{
    import core.stdc.string: memset;

    auto context = cast(LLTaskProperties*) malloc(LLTaskProperties.sizeof);
    if(!context) return ThreadID.init;

    *context = LLTaskProperties(dg);

    import core.thread.types: ll_ThreadData;

    lowlevelLock.lock_nothrow();
    scope(exit) lowlevelLock.unlock_nothrow();

    ll_nThreads++;
    auto new_ll_pThreads = cast(ll_ThreadData*) realloc(ll_pThreads, ll_ThreadData.sizeof * ll_nThreads);
    if(!new_ll_pThreads) return ThreadID.init;
    ll_pThreads = new_ll_pThreads;

    if(stacksize == 0)
        stacksize = DefaultStackSize;

    version (ESP_IDF)
    {
        if(stacksize < os.configMINIMAL_STACK_SIZE)
            return ThreadID.init;
    }
    else
    {
        auto wordsStackSize = stacksize / os.StackType_t.sizeof;
        if(wordsStackSize < os.configMINIMAL_STACK_SIZE)
            return ThreadID.init;
    }

    auto stackBuff = cast(os.StackType_t*) aligned_alloc(os.StackType_t.sizeof, stacksize);
    auto tcb = cast(os.StaticTask_t*) malloc(os.StaticTask_t.sizeof);

    auto currThread = &ll_pThreads[ll_nThreads - 1];
    memset(currThread, 0x00, ll_ThreadData.sizeof);
    currThread.initialize();

    version (ESP_IDF)
    {
        currThread.tid = xTaskCreateStaticPinnedToCore(
            &lowlevelThread_entryPoint,
            params.name,
            stacksize,
            cast(void*) context, // pvParameters*
            DefaultTaskPriority,
            stackBuff,
            tcb,
            Thread.xCoreID
        );
    }
    else
    {
        currThread.tid = os.xTaskCreateStatic(
            &lowlevelThread_entryPoint,
            params.name,
            wordsStackSize,
            cast(void*) context, // pvParameters*
            DefaultTaskPriority,
            stackBuff,
            tcb
        );
    }

    // xTaskCreateStatic returns 0 if some error occured, ensure what this is ThreadID.init
    static assert(ThreadID.init is null);

    return currThread.tid;
}

private extern(C) void lowlevelThread_entryPoint(void* ctx) nothrow
{
    LLTaskProperties lltp = *cast(LLTaskProperties*) ctx; 
    free(ctx);

    lltp.dg();

    ThreadID tid = getThreadID();

    lowlevelLock.lock_nothrow();

    ll_ThreadData* td = getLLThreadNotThreadSafe(tid);
    assert(td);

    td.joinEvent.setIfInitialized();

    lowlevelLock.unlock_nothrow();

    //FIXME: replace this dumb condvar implementation
    while(td.getSubscribersNum() != 0)
    {
        os.vTaskDelay(100); // ticks, 0.1 second
    }

    ll_removeThread(tid);

    os.vTaskDelete(null);
}

void joinLowLevelThread(in ThreadID tid) nothrow @nogc
{
    ll_ThreadData* t = lockAndGetLowLevelThread(tid);

    if(t is null) // thread already exited
        return;

    t.joinEvent.wait();

    t.deletionUnlock(); // then thread can be safely deleted
}

private ll_ThreadData* lockAndGetLowLevelThread(in ThreadID tid) nothrow @nogc
{
    lowlevelLock.lock_nothrow();

    auto t = getLLThreadNotThreadSafe(tid);

    // thread still not deleted? lock its deletion
    if(t !is null)
        t.deletionLock();

    lowlevelLock.unlock_nothrow();

    return t;
}

private ll_ThreadData* getLLThreadNotThreadSafe(in ThreadID tid) nothrow @nogc
{
    foreach (i; 0 .. ll_nThreads)
    {
        auto curr = &ll_pThreads[i];

        if (tid is curr.tid)
            return curr;
    }

    return null;
}

@nogc:

//TODO: move to threadbase?
/// Init threads module
extern (C) void thread_init() @nogc
{
    import core.internal.entrypoint: initMainStack;

    initMainStack();
    initLowlevelThreads();
    ThreadBase.initLocks();

    // Threads storage
    assert(typeid(Thread).initializer.ptr);
    _mainThreadStore[] = typeid(Thread).initializer[];

    // Creating main thread
    Thread mainThread = (cast(Thread) _mainThreadStore.ptr).__ctor();

    import core.internal.entrypoint: mainTaskProperties;
    mainThread.m_main.bstack = mainTaskProperties.stackBottom;

    ThreadBase.sm_main = attachThread(mainThread);
}

private alias MainThreadStore = void[__traits(classInstanceSize, Thread)];
private  __gshared align(__traits(classInstanceAlignment, Thread)) MainThreadStore _mainThreadStore;

/// Term threads module
extern (C) void thread_term() @nogc
{
    thread_term_tpl!(Thread)(_mainThreadStore);
}

nothrow:

extern (C) static Thread thread_findByAddr(ThreadID addr)
{
    assert(false, "Not implemented");
}

extern (C) void thread_suspendHandler( int sig ) nothrow
{
    assert(false, "Not implemented");
}

extern (C) void thread_resumeHandler( int sig ) nothrow
{
    assert(false, "Not implemented");
}

/// Suspend all threads but the calling thread
extern (C) void thread_suspendAll() nothrow
{
    if ( !multiThreadedFlag && Thread.sm_tbeg )
    {
        if ( ++suspendDepth == 1 )
            suspend( Thread.getThis() );

        return;
    }

    ThreadBase.slock.lock_nothrow();

    {
        if ( ++suspendDepth > 1 )
            return;

        ThreadBase.criticalRegionLock.lock_nothrow();
        scope (exit) ThreadBase.criticalRegionLock.unlock_nothrow();

        size_t cnt;
        Thread t = ThreadBase.sm_tbeg.toThread;

        while (t)
        {
            auto tn = t.next.toThread;
            if (suspend(t))
                ++cnt;
            t = tn;
        }

        assert(cnt >= 1);
    }
}

/// Suspend the specified thread and load stack and register information
private extern (D) bool suspend( Thread t ) nothrow
{
    // Common code (TODO: use druntime code instead?):

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

    // OS-specific code:

    if (t.m_addr != os.xTaskGetCurrentTaskHandle())
    {
        os.vTaskSuspend(t.m_addr);
    }
    else if (!t.m_lock)
    {
        t.m_curr.tstack = getStackTop();
    }

    return true;
}

private extern(D) void resume(ThreadBase _t) nothrow @nogc
{
    Thread t = _t.toThread;

    if(t.m_addr != os.xTaskGetCurrentTaskHandle())
    {
        os.vTaskResume(t.m_addr);
    }
    else if ( !t.m_lock )
    {
        t.m_curr.tstack = t.m_curr.bstack;
    }
}

void thread_intermediateShutdown() nothrow @nogc
{
    assert(false, "Not implemented");
}

void* getStackBottom() nothrow @nogc
{
    assert(Thread.getThis().m_main.bstack !is null);

    return Thread.getThis().m_main.bstack;
}

bool findLowLevelThread(ThreadID tid) nothrow @nogc
{
    assert(false, "Not implemented");
}

ThreadBase attachThread(ThreadBase thisThread) @nogc nothrow
{
    Thread t = thisThread.toThread;

    StackContext* thisContext = &thisThread.m_main;
    assert(thisContext);
    assert(thisContext == t.m_curr);

    t.m_addr = os.xTaskGetCurrentTaskHandle();
    assert(thisContext.bstack);
    thisContext.tstack = thisContext.bstack;

    t.isRunning = true;
    t.m_isDaemon = true;
    t.tlsGCdataInit();
    Thread.setThis(t);

    ThreadBase.add( t, false );
    ThreadBase.add( thisContext );
    if ( Thread.sm_main !is null )
        multiThreadedFlag = true;

    return t;
}

class Thread : ThreadBase
{
    private TaskProperties taskProperties;
    private shared bool m_isRunning;

    /// Initializes a thread object which has no associated executable function.
    /// This is used for the main thread initialized in thread_init().
    this(size_t sz = 0) @safe pure nothrow @nogc
    {
    }

    this(void function() fn, size_t sz = 0, /* string file = __FILE__, size_t line = __LINE__ */) @safe nothrow
    in(fn !is null)
    {
        super(fn, sz);
        initTaskProperties();
        taskProperties.joinEvent = EventAwaiter(true, false);
        //printTcbCreated(file, line);
    }

    this(void delegate() dg, size_t sz = 0, /* string file = __FILE__, size_t line = __LINE__ */) @safe nothrow
    in(dg !is null)
    {
        super(dg, sz);
        initTaskProperties();
        taskProperties.joinEvent = EventAwaiter(true, false);
        //printTcbCreated(file, line);
    }

    ~this() nothrow @nogc
    {
        if(taskProperties.stackBuff) // not main thread
            free(taskProperties.stackBuff);

        destructBeforeDtor();
    }

    private void initTaskProperties() @safe nothrow
    {
        import core.exception: onOutOfMemoryError;

        if(m_sz == 0)
            m_sz = DefaultStackSize;

        assert(m_sz <= ushort.max * size_t.sizeof, "FreeRTOS stack size limit");
        assert(m_sz % os.StackType_t.sizeof == 0, "Stack size must be multiple of word");

        taskProperties.stackBuff = (() @trusted => aligned_alloc(os.StackType_t.sizeof, m_sz))();
        if(!taskProperties.stackBuff)
            onOutOfMemoryError();

        m_main.bstack = (() @trusted => taskProperties.stackBuff + m_sz - 1)();
    }

    private void printTcbCreated(string file, size_t line) @trusted nothrow
    {
        debug(PRINTF)
        {
            import core.stdc.stdio: printf;

            printf("TCB %p created from file %s line %d\n", &taskProperties.tcb, cast(char*) file, line);
        }
    }

    private void initDataStorage() nothrow
    {
        assert(m_curr is &m_main);

        assert(m_main.bstack);
        m_main.tstack = m_main.bstack;

        tlsGCdataInit();
    }

    override final void run()
    {
        super.run();
    }

    version (ESP_IDF)
    {
        private __gshared os.BaseType_t xCoreID = os.BaseType_t.max; // tskNO_AFFINITY

        /**
        Params:
            id = specify the created task's core affinity. The valid values for core affinity are:
                0, which pins the created task to Core 0
                1, which pins the created task to Core 1
                tskNO_AFFINITY, which allows the task to be run on both cores
        */
        void setNextCoreId(os.BaseType_t id)
        {
            import core.atomic: atomicStore;

            atomicStore(xCoreID, id);
        }
    }

    final Thread start() nothrow
    {
        auto wasThreaded  = multiThreadedFlag;
        multiThreadedFlag = true;
        scope( failure )
        {
            if ( !wasThreaded )
                multiThreadedFlag = false;
        }

        slock.lock_nothrow();
        scope(exit) slock.unlock_nothrow();

        {
            ++nAboutToStart;
            pAboutToStart = cast(ThreadBase*)realloc(pAboutToStart, Thread.sizeof * nAboutToStart);
            pAboutToStart[nAboutToStart - 1] = this;

            version (ESP_IDF)
            {
                assert(m_sz >= os.configMINIMAL_STACK_SIZE);
            }
            else
            {
                auto wordsStackSize = m_sz / os.StackType_t.sizeof;
                assert(wordsStackSize >= os.configMINIMAL_STACK_SIZE);
            }

            isRunning = true;
            scope(failure) isRunning = false;

            immutable name = "D thread"; //FIXME: fill name from m_name

            version (ESP_IDF)
            {
                m_addr = xTaskCreateStaticPinnedToCore(
                    &thread_entryPoint,
                    cast(const(char*)) name,
                    m_sz,
                    cast(void*) this, // pvParameters*
                    DefaultTaskPriority,
                    cast(os.StackType_t*) taskProperties.stackBuff,
                    &(taskProperties.tcb),
                    xCoreID
                );
            }
            else
            {
                m_addr = os.xTaskCreateStatic(
                    &thread_entryPoint,
                    cast(const(char*)) name,
                    wordsStackSize,
                    cast(void*) this, // pvParameters*
                    DefaultTaskPriority,
                    cast(os.StackType_t*) taskProperties.stackBuff,
                    &(taskProperties.tcb)
                );
            }

            return this;
        }
    }

    static Thread getThis() @safe nothrow @nogc
    {
        return cast(Thread) ThreadBase.getThis;
    }

    @property static int PRIORITY_MIN() @nogc nothrow pure @safe
    {
        assert(false, "unimplemented");
    }

    @property static const(int) PRIORITY_MAX() @nogc nothrow pure @safe
    {
        assert(false, "unimplemented");
    }

    @property static int PRIORITY_DEFAULT() @nogc nothrow pure @safe
    {
        assert(false, "unimplemented");
    }

    final @property int priority()
    {
        assert(false, "unimplemented");
    }

    final @property void priority(int val)
    in(val >= PRIORITY_MIN)
    in(val <= PRIORITY_MAX)
    {
        assert(false, "unimplemented");
    }

    import core.atomic: atomicStore, atomicLoad, MemoryOrder;

    private void isRunning(bool status) @property nothrow @nogc
    {
        atomicStore!(MemoryOrder.raw)(m_isRunning, status);
    }

    override final @property bool isRunning() nothrow @nogc
    {
        if (!super.isRunning())
            return false;

        return atomicLoad(m_isRunning);
    }

    //
    // Remove a thread from the global thread list.
    //
    static void remove(Thread t) nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    override final Throwable join( bool rethrow = true )
    {
        assert(taskProperties.stackBuff !is null, "Can't join main thread");

        taskProperties.joinEvent.wait();

        m_addr = m_addr.init;

        if (m_unhandled)
        {
            if (rethrow)
                throw m_unhandled;
            return m_unhandled;
        }

        return null;
    }

    static void sleep(Duration val) @nogc nothrow @trusted
    {
        import os = internal.binding;
        import core.time: toTicks;

        os.vTaskDelay(val.toTicks);
    }

    static void yield() @nogc nothrow
    {
        _taskYield();
    }
}

private void _taskYield() @nogc nothrow
{
    import ldc.llvmasm;

    version(ARM)
    {
        // taskYield() code what dpp can't convert from FreeRTOS headers

        /* Set a PendSV to request a context switch. */
        //os.portNVIC_INT_CTRL_REG = os.portNVIC_PENDSVSET_BIT;
        __gshared ulong* portNVIC_INT_CTRL_REG = cast(ulong*) 0xe000ed04;
        *portNVIC_INT_CTRL_REG = os.portNVIC_PENDSVSET_BIT;

        /* Barriers are normally not required but do ensure the code is completely
         * within the specified behaviour for the architecture. */
        // __asm volatile ( "dsb" ::: "memory" );
        // __asm volatile ( "isb" );

        __asm!()(`dsb`, "~{memory}");
        __asm!()(`isb`, "");
    }
    else version(RISCV32)
    {
        // __asm volatile ( "ecall" );
        __asm!()(`ecall`, "");
    }
    else
        static assert(false, "Not implemented");
}

private Thread toThread(ThreadBase t) @trusted nothrow @nogc pure
{
    return cast(Thread) cast(void*) t;
}

// Picolibc malloc threads support:
private:

shared SpinLock memLock = SpinLock(SpinLock.Contention.lengthy);

extern(C) void __malloc_lock()
{
    memLock.lock();
}

extern(C) void __malloc_unlock()
{
    memLock.unlock();
}

version (ESP_IDF)
extern(C)
os.TaskHandle_t xTaskCreateStaticPinnedToCore(
    os.TaskFunction_t pxTaskCode,
    const(const(char)*) pcName,
    const uint ulStackDepth,
    void* pvParameters,
    os.UBaseType_t uxPriority,
    os.StackType_t* pxStackBuffer,
    os.StaticTask_t* pxTaskBuffer,
    const os.BaseType_t xCoreID
) nothrow @nogc;
