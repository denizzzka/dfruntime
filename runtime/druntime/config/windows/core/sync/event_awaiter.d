module core.sync.event_awaiter;

import core.sys.windows.basetsd /+: HANDLE +/;
import core.sys.windows.winerror /+: WAIT_TIMEOUT +/;
import core.sys.windows.winbase /+: CreateEvent, CloseHandle, SetEvent, ResetEvent,
    WaitForSingleObject, INFINITE, WAIT_OBJECT_0+/;

import core.time;
import core.internal.abort : abort;

struct EventAwaiter
{
nothrow @nogc:

private HANDLE m_event;

    /**
     * Creates an event object.
     *
     * Params:
     *  manualReset  = the state of the event is not reset automatically after resuming waiting clients
     *  initialState = initial state of the signal
     */
    this(bool manualReset, bool initialState)
    {
        m_event = CreateEvent(null, manualReset, initialState, null);
        m_event || abort("Error: CreateEvent failed.");
    }

    ~this()
    {
        if (m_event)
            CloseHandle(m_event);
    }

    // copying not allowed, can produce resource leaks
    @disable this(this);
    @disable void opAssign(EventAwaiter);

    /// Set the event to "signaled", so that waiting clients are resumed
    void set()
    {
        SetEvent(m_event);
    }

    /// Reset the event manually
    void reset()
    {
        ResetEvent(m_event);
    }

    /**
     * Wait for the event to be signaled without timeout.
     *
     * Returns:
     *  `true` if the event is in signaled state, `false` if the event is uninitialized or another error occured
     */
    bool wait()
    {
        return WaitForSingleObject(m_event, INFINITE) == WAIT_OBJECT_0;
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
        auto maxWaitMillis = dur!("msecs")(uint.max - 1);

        while (tmout > maxWaitMillis)
        {
            auto res = WaitForSingleObject(m_event, uint.max - 1);
            if (res != WAIT_TIMEOUT)
                return res == WAIT_OBJECT_0;
            tmout -= maxWaitMillis;
        }
        auto ms = cast(uint)(tmout.total!"msecs");
        return WaitForSingleObject(m_event, ms) == WAIT_OBJECT_0;
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
