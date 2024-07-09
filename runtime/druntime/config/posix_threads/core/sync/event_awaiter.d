module core.sync.event_awaiter;

import core.sys.posix.pthread;
import core.sys.posix.sys.types;
import core.sys.posix.time;

import core.time;
import core.internal.abort : abort;

//TODO: use core.sync.mutex here?

/*
Checking whether the Event object is in initialized state every time
then any of its methods are called is waste of CPU resources

I propose to intruduce new EventAwaiter struct which provides RAII interface
and methods doesn't poisoned by if(m_initalized) checks
*/
struct EventAwaiter
{
nothrow @nogc:

private
{
    pthread_mutex_t m_mutex;
    pthread_cond_t m_cond;
    bool m_state;
    bool m_manualReset;
}

    /**
     * Creates an event object.
     *
     * Params:
     *  manualReset  = the state of the event is not reset automatically after resuming waiting clients
     *  initialState = initial state of the signal
     */
    this(bool manualReset, bool initialState)
    {
        pthread_mutex_init(cast(pthread_mutex_t*) &m_mutex, null) == 0 ||
            abort("Error: pthread_mutex_init failed.");
        static if ( is( typeof( pthread_condattr_setclock ) ) )
        {
            pthread_condattr_t attr = void;
            pthread_condattr_init(&attr) == 0 ||
                abort("Error: pthread_condattr_init failed.");
            pthread_condattr_setclock(&attr, CLOCK_MONOTONIC) == 0 ||
                abort("Error: pthread_condattr_setclock failed.");
            pthread_cond_init(&m_cond, &attr) == 0 ||
                abort("Error: pthread_cond_init failed.");
            pthread_condattr_destroy(&attr) == 0 ||
                abort("Error: pthread_condattr_destroy failed.");
        }
        else
        {
            pthread_cond_init(&m_cond, null) == 0 ||
                abort("Error: pthread_cond_init failed.");
        }
        m_state = initialState;
        m_manualReset = manualReset;
    }

    ~this()
    {
        pthread_mutex_destroy(&m_mutex) == 0 ||
            abort("Error: pthread_mutex_destroy failed.");
        pthread_cond_destroy(&m_cond) == 0 ||
            abort("Error: pthread_cond_destroy failed.");
    }

    // copying not allowed, can produce resource leaks
    @disable this(this);
    @disable void opAssign(EventAwaiter);

    /// Set the event to "signaled", so that waiting clients are resumed
    void set()
    {
        pthread_mutex_lock(&m_mutex);
        m_state = true;
        pthread_cond_broadcast(&m_cond);
        pthread_mutex_unlock(&m_mutex);
    }

    /// Reset the event manually
    void reset()
    {
        pthread_mutex_lock(&m_mutex);
        m_state = false;
        pthread_mutex_unlock(&m_mutex);
    }

    /**
     * Wait for the event to be signaled without timeout.
     *
     * Returns:
     *  `true` if the event is in signaled state, `false` if the event is uninitialized or another error occured
     */
    bool wait()
    {
        return wait(Duration.max);
    }

    /**
     * Wait for the event to be signaled with timeout.
     *
     * Params:
     *  tmout = the maximum time to wait
     * Returns:
     *  `true` if the event is in signaled state, `false` if the event was nonsignaled for the given time or
     *  the event is uninitialized or another error occured
     */
    bool wait(Duration tmout)
    {
        pthread_mutex_lock(&m_mutex);

        int result = 0;
        if (!m_state)
        {
            if (tmout == Duration.max)
            {
                result = pthread_cond_wait(&m_cond, &m_mutex);
            }
            else
            {
                import core.sync.config;

                timespec t = void;
                mktspec(t, tmout);

                result = pthread_cond_timedwait(&m_cond, &m_mutex, &t);
            }
        }
        if (result == 0 && !m_manualReset)
            m_state = false;

        pthread_mutex_unlock(&m_mutex);

        return result == 0;
    }
}

// Test single-thread (non-shared) use.
@nogc nothrow unittest
{
    // auto-reset, initial state false
    EventAwaiter ev1 = EventAwaiter(false, false);
    assert(!ev1.wait(1.dur!"msecs"));
    ev1.set();
    assert(ev1.wait());
    assert(!ev1.wait(1.dur!"msecs"));

    // manual-reset, initial state true
    EventAwaiter ev2 = EventAwaiter(true, true);
    assert(ev2.wait());
    assert(ev2.wait());
    ev2.reset();
    assert(!ev2.wait(1.dur!"msecs"));
}

unittest
{
    import core.thread, core.atomic;

    scope event      = new EventAwaiter(true, false);
    int  numThreads = 10;
    shared int numRunning = 0;

    void testFn()
    {
        event.wait(8.dur!"seconds"); // timeout below limit for druntime test_runner
        numRunning.atomicOp!"+="(1);
    }

    auto group = new ThreadGroup;

    for (int i = 0; i < numThreads; ++i)
        group.create(&testFn);

    auto start = MonoTime.currTime;
    assert(numRunning == 0);

    event.set();
    group.joinAll();

    assert(numRunning == numThreads);

    assert(MonoTime.currTime - start < 5.dur!"seconds");
}
