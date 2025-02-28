/**
 * The mutex module provides a primitive for maintaining mutually exclusive
 * access.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Denis Feklushkin
 * Source:    $(DRUNTIMESRC config/freertos/core/sync/mutex.d)
 */
module core.sync.mutex;

import object;
import internal.binding /*freertos_binding*/;

@nogc:

class Mutex : Object.Monitor
{
    import core.sync.exception;
    import core.internal.abort;

    private SemaphoreHandle_t mtx = void;

    this(Object obj) @trusted nothrow @nogc
    {
        this();
        obj.__monitor = cast(void*) this;
    }

    this() @nogc nothrow @trusted
    {
        mtx = _xSemaphoreCreateRecursiveMutex();

        if(mtx is null)
            abort("Error: memory required to hold mutex could not be allocated.");
    }

    this() @nogc shared nothrow @safe
    {
        assert(false);
    }

    ~this() @nogc nothrow
    {
        _vSemaphoreDelete(mtx);
    }

    final void lock_nothrow(this Q)() nothrow @trusted @nogc
    if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        // Infinity wait
        if(xSemaphoreTakeMutexRecursive(mtx.unshare, portMAX_DELAY) != pdTRUE)
        {
            SyncError syncErr = cast(SyncError) cast(void*) typeid(SyncError).initializer;
            syncErr.msg = "Unable to lock mutex.";
            throw syncErr;
        }
    }

    final bool tryLock_nothrow(this Q)() nothrow @safe @nogc
        if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        //FIXME: lock_nothrow can lock into infinity wait
        lock_nothrow();

        return true;
    }

    final void unlock_nothrow(this Q)() nothrow @trusted @nogc
    if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        if(xSemaphoreGiveMutexRecursive(mtx.unshare) != pdTRUE)
        {
            SyncError syncErr = cast(SyncError) cast(void*) typeid(SyncError).initializer;
            syncErr.msg = "Unable to unlock mutex.";
            throw syncErr;
        }
    }

    @trusted void lock()
    {
        lock_nothrow();
    }

    /// ditto
    @trusted void lock() shared
    {
        lock_nothrow();
    }

    bool tryLock() @safe
    {
        return tryLock_nothrow();
    }

    @trusted void unlock()
    {
        unlock_nothrow();
    }

    /// ditto
    @trusted void unlock() shared
    {
        unlock_nothrow();
    }
}

private QueueDefinition* unshare(T)(T mtx) pure nothrow
{
    return cast(QueueDefinition*) mtx;
}
