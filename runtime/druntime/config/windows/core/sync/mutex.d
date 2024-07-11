/**
 * The mutex module provides a primitive for maintaining mutually exclusive
 * access.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Sean Kelly
 * Source:    $(DRUNTIMESRC core/sync/_mutex.d)
 */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sync.mutex;


public import core.sync.exception;

import core.sys.windows.winbase /+: CRITICAL_SECTION, DeleteCriticalSection,
    EnterCriticalSection, InitializeCriticalSection, LeaveCriticalSection,
    TryEnterCriticalSection+/;

////////////////////////////////////////////////////////////////////////////////
// Mutex
//
// void lock();
// void unlock();
// bool tryLock();
////////////////////////////////////////////////////////////////////////////////


/**
 * This class represents a general purpose, recursive mutex.
 *
 * Implemented using `pthread_mutex` on Posix and `CRITICAL_SECTION`
 * on Windows.
 */
class Mutex :
    Object.Monitor
{
    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Initializes a mutex object.
     *
     */
    this() @trusted nothrow @nogc
    {
        this(true);
    }

    /// ditto
    this() shared @trusted nothrow @nogc
    {
        this(true);
    }

    // Undocumented, useful only in Mutex.this().
    private this(this Q)(bool _unused_) @trusted nothrow @nogc
        if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        InitializeCriticalSection(cast(CRITICAL_SECTION*) &m_hndl);
        m_proxy.link = this;
        this.__monitor = cast(void*) &m_proxy;
    }


    /**
     * Initializes a mutex object and sets it as the monitor for `obj`.
     *
     * In:
     *  `obj` must not already have a monitor.
     */
    this(Object obj) @trusted nothrow @nogc
    {
        this(obj, true);
    }

    /// ditto
    this(Object obj) shared @trusted nothrow @nogc
    {
        this(obj, true);
    }

    // Undocumented, useful only in Mutex.this(Object).
    private this(this Q)(Object obj, bool _unused_) @trusted nothrow @nogc
        if (is(Q == Mutex) || is(Q == shared Mutex))
    in
    {
        assert(obj !is null,
            "The provided object must not be null.");
        assert(obj.__monitor is null,
            "The provided object has a monitor already set!");
    }
    do
    {
        this();
        obj.__monitor = cast(void*) &m_proxy;
    }


    ~this() @trusted nothrow @nogc
    {
        DeleteCriticalSection(&m_hndl);
        this.__monitor = null;
    }


    ////////////////////////////////////////////////////////////////////////////
    // General Actions
    ////////////////////////////////////////////////////////////////////////////


    /**
     * If this lock is not already held by the caller, the lock is acquired,
     * then the internal counter is incremented by one.
     *
     * Note:
     *    `Mutex.lock` does not throw, but a class derived from Mutex can throw.
     *    Use `lock_nothrow` in `nothrow @nogc` code.
     */
    @trusted void lock()
    {
        lock_nothrow();
    }

    /// ditto
    @trusted void lock() shared
    {
        lock_nothrow();
    }

    /// ditto
    final void lock_nothrow(this Q)() nothrow @trusted @nogc
        if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        EnterCriticalSection(&m_hndl);
    }

    /**
     * Decrements the internal lock count by one.  If this brings the count to
     * zero, the lock is released.
     *
     * Note:
     *    `Mutex.unlock` does not throw, but a class derived from Mutex can throw.
     *    Use `unlock_nothrow` in `nothrow @nogc` code.
     */
    @trusted void unlock()
    {
        unlock_nothrow();
    }

    /// ditto
    @trusted void unlock() shared
    {
        unlock_nothrow();
    }

    /// ditto
    final void unlock_nothrow(this Q)() nothrow @trusted @nogc
        if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        LeaveCriticalSection(&m_hndl);
    }

    /**
     * If the lock is held by another caller, the method returns.  Otherwise,
     * the lock is acquired if it is not already held, and then the internal
     * counter is incremented by one.
     *
     * Returns:
     *  true if the lock was acquired and false if not.
     *
     * Note:
     *    `Mutex.tryLock` does not throw, but a class derived from Mutex can throw.
     *    Use `tryLock_nothrow` in `nothrow @nogc` code.
     */
    bool tryLock() @trusted
    {
        return tryLock_nothrow();
    }

    /// ditto
    bool tryLock() shared @trusted
    {
        return tryLock_nothrow();
    }

    /// ditto
    final bool tryLock_nothrow(this Q)() nothrow @trusted @nogc
        if (is(Q == Mutex) || is(Q == shared Mutex))
    {
        return TryEnterCriticalSection(&m_hndl) != 0;
    }


private:
    CRITICAL_SECTION    m_hndl;

    struct MonitorProxy
    {
        Object.Monitor link;
    }

    MonitorProxy            m_proxy;
}
