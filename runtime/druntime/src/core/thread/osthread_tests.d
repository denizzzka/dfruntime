module core.thread.osthread_tests;

import core.atomic;
import core.memory: pageSize;
import core.thread.osthread;
import core.thread.threadbase;
import core.thread.types: ThreadID;

///
version (ThreadsDisabled) {} else
{
unittest
{
    class DerivedThread : Thread
    {
        this()
        {
            super(&run);
        }

    private:
        void run()
        {
            // Derived thread running.
        }
    }

    void threadFunc()
    {
        // Composed thread running.
    }

    // create and start instances of each type
    auto derived = new DerivedThread().start();
    auto composed = new Thread(&threadFunc).start();
    new Thread({
        // Codes to run in the newly created thread.
    }).start();
}

unittest
{
    int x = 0;

    new Thread(
    {
        x++;
    }).start().join();
    assert( x == 1 );
}


unittest
{
    enum MSG = "Test message.";
    string caughtMsg;

    try
    {
        new Thread(
        function()
        {
            throw new Exception( MSG );
        }).start().join();
        assert( false, "Expected rethrown exception." );
    }
    catch ( Throwable t )
    {
        assert( t.msg == MSG );
    }
}


unittest
{
    // use >pageSize to avoid stack overflow (e.g. in an syscall)
    auto thr = new Thread(function{}, pageSize + 8 /* stack size aligned for most platforms */).start();
    thr.join();
}


unittest
{
    import core.memory : GC;

    auto t1 = new Thread({
        foreach (_; 0 .. 20)
            ThreadBase.getAll;
    }).start;
    auto t2 = new Thread({
        foreach (_; 0 .. 20)
            GC.collect;
    }).start;
    t1.join();
    t2.join();
}

unittest
{
    import core.sync.semaphore;
    auto sem = new Semaphore();

    auto t = new Thread(
    {
        sem.notify();
        Thread.sleep(100.msecs);
    }).start();

    sem.wait(); // thread cannot be detached while being started
    thread_detachInstance(t);
    foreach (t2; Thread)
        assert(t !is t2);
    t.join();
}

unittest
{
    // NOTE: This entire test is based on the assumption that no
    //       memory is allocated after the child thread is
    //       started. If an allocation happens, a collection could
    //       trigger, which would cause the synchronization below
    //       to cause a deadlock.
    // NOTE: DO NOT USE LOCKS IN CRITICAL REGIONS IN NORMAL CODE.

    import core.sync.semaphore;

    auto sema = new Semaphore(),
         semb = new Semaphore();

    auto thr = new Thread(
    {
        thread_enterCriticalRegion();
        assert(thread_inCriticalRegion());
        sema.notify();

        semb.wait();
        assert(thread_inCriticalRegion());

        thread_exitCriticalRegion();
        assert(!thread_inCriticalRegion());
        sema.notify();

        semb.wait();
        assert(!thread_inCriticalRegion());
    });

    thr.start();

    sema.wait();
    synchronized (ThreadBase.criticalRegionLock)
        assert(thr.m_isInCriticalRegion);
    semb.notify();

    sema.wait();
    synchronized (ThreadBase.criticalRegionLock)
        assert(!thr.m_isInCriticalRegion);
    semb.notify();

    thr.join();
}

// https://issues.dlang.org/show_bug.cgi?id=22124
unittest
{
    Thread thread = new Thread({});
    auto fun(Thread t, int x)
    {
        t.__ctor({x = 3;});
        return t;
    }
    static assert(!__traits(compiles, () @nogc => fun(thread, 3) ));
}

unittest
{
    import core.sync.semaphore;

    shared bool inCriticalRegion;
    auto sema = new Semaphore(),
         semb = new Semaphore();

    auto thr = new Thread(
    {
        thread_enterCriticalRegion();
        inCriticalRegion = true;
        sema.notify();
        semb.wait();

        Thread.sleep(dur!"msecs"(1));
        inCriticalRegion = false;
        thread_exitCriticalRegion();
    });
    thr.start();

    sema.wait();
    assert(inCriticalRegion);
    semb.notify();

    thread_suspendAll();
    assert(!inCriticalRegion);
    thread_resumeAll();
}
}

@nogc @safe nothrow
unittest
{
    import core.time;
    Thread.sleep(1.msecs);
}

// regression test for Issue 13416
version (FreeBSD) unittest
{
    static void loop()
    {
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        auto thr = pthread_self();
        foreach (i; 0 .. 50)
            pthread_attr_get_np(thr, &attr);
        pthread_attr_destroy(&attr);
    }

    auto thr = new Thread(&loop).start();
    foreach (i; 0 .. 50)
    {
        thread_suspendAll();
        thread_resumeAll();
    }
    thr.join();
}

version (DragonFlyBSD) unittest
{
    static void loop()
    {
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        auto thr = pthread_self();
        foreach (i; 0 .. 50)
            pthread_attr_get_np(thr, &attr);
        pthread_attr_destroy(&attr);
    }

    auto thr = new Thread(&loop).start();
    foreach (i; 0 .. 50)
    {
        thread_suspendAll();
        thread_resumeAll();
    }
    thr.join();
}

version (ThreadsDisabled) {}
else:

nothrow @nogc unittest
{
    struct TaskWithContect
    {
        shared int n = 0;
        void run() nothrow
        {
            n.atomicOp!"+="(1);
        }
    }
    TaskWithContect task;

    ThreadID[8] tids;
    for (int i = 0; i < tids.length; i++)
    {
        tids[i] = createLowLevelThread(&task.run);
        assert(tids[i] != ThreadID.init);
    }

    for (int i = 0; i < tids.length; i++)
        joinLowLevelThread(tids[i]);

    assert(task.n == tids.length);
}

unittest
{
    auto thr = Thread.getThis();
    immutable prio = thr.priority;
    scope (exit) thr.priority = prio;

    assert(prio == thr.PRIORITY_DEFAULT);
    assert(prio >= thr.PRIORITY_MIN && prio <= thr.PRIORITY_MAX);
    thr.priority = thr.PRIORITY_MIN;
    assert(thr.priority == thr.PRIORITY_MIN);
    thr.priority = thr.PRIORITY_MAX;
    assert(thr.priority == thr.PRIORITY_MAX);
}

unittest // Bugzilla 8960
{
    import core.sync.semaphore;

    auto thr = new Thread({});
    thr.start();
    Thread.sleep(1.msecs);       // wait a little so the thread likely has finished
    thr.priority = thr.PRIORITY_MAX; // setting priority doesn't cause error
    auto prio = thr.priority;    // getting priority doesn't cause error
    assert(prio >= thr.PRIORITY_MIN && prio <= thr.PRIORITY_MAX);
}
