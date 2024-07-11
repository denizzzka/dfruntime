module core.sync.mutex_tests;

import core.sync.mutex;

///
/* @safe nothrow -> see druntime PR 1726 */
// Test regular usage.
unittest
{
    import core.thread : Thread;

    class Resource
    {
        Mutex mtx;
        int cargo;

        this() shared @safe nothrow
        {
            mtx = new shared Mutex();
            cargo = 42;
        }

        void useResource() shared @trusted nothrow @nogc
        {
            mtx.lock_nothrow();
            (cast() cargo) += 1;
            mtx.unlock_nothrow();
        }
    }

    shared Resource res = new shared Resource();

    auto otherThread = new Thread(
    {
        foreach (i; 0 .. 10000)
            res.useResource();
    }).start();

    foreach (i; 0 .. 10000)
        res.useResource();

    otherThread.join();

    assert (res.cargo == 20042);
}

// Test @nogc usage.
@system @nogc nothrow unittest
{
    import core.stdc.stdlib : malloc, free;
    import core.lifetime : emplace;

    auto mtx = cast(shared Mutex) malloc(__traits(classInstanceSize, Mutex));
    emplace(mtx);

    mtx.lock_nothrow();

    { // test recursive locking
        mtx.tryLock_nothrow();
        mtx.unlock_nothrow();
    }

    mtx.unlock_nothrow();

    // In general destorying classes like this is not
    // safe, but since we know that the only base class
    // of Mutex is Object and it doesn't have a dtor
    // we can simply call the non-virtual __dtor() here.

    // Ok to cast away shared because destruction
    // should happen only from a single thread.
    (cast(Mutex) mtx).__dtor();

    // Verify that the underlying implementation has been destroyed by checking
    // that locking is not possible. This assumes that the underlying
    // implementation is well behaved and makes the object non-lockable upon
    // destruction. The Bionic, DragonFly, Musl, and Solaris C runtimes don't
    // appear to do so, so skip this test.
    version (CRuntime_Bionic) {} else
    version (CRuntime_Musl) {} else
    version (DragonFlyBSD) {} else
    version (Solaris) {} else
    assert(!mtx.tryLock_nothrow());

    free(cast(void*) mtx);
}


// Test single-thread (non-shared) use.
unittest
{
    Mutex m = new Mutex();

    m.lock();

    m.tryLock();
    m.unlock();

    m.unlock();
}

unittest
{
    import core.thread;

    auto mutex      = new Mutex;
    int  numThreads = 10;
    int  numTries   = 1000;
    int  lockCount  = 0;

    void testFn()
    {
        for (int i = 0; i < numTries; ++i)
        {
            synchronized (mutex)
            {
                ++lockCount;
            }
        }
    }

    auto group = new ThreadGroup;

    for (int i = 0; i < numThreads; ++i)
        group.create(&testFn);

    group.joinAll();
    assert(lockCount == numThreads * numTries);
}
