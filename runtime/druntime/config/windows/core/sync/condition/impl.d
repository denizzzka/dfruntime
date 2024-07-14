/**
 * The condition module provides a primitive for synchronized condition
 * checking.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Sean Kelly
 * Source:    $(DRUNTIMESRC core/sync/_condition.d)
 */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sync.condition.impl;

import core.sync.mutex: Mutex;
import core.time: Duration;

import core.exception : AssertError, staticError;

import core.sync.semaphore;
import core.sys.windows.basetsd /+: HANDLE+/;
import core.sys.windows.winbase /+: CloseHandle, CreateSemaphoreA, CRITICAL_SECTION,
    DeleteCriticalSection, EnterCriticalSection, INFINITE, InitializeCriticalSection,
    LeaveCriticalSection, ReleaseSemaphore, WAIT_OBJECT_0, WaitForSingleObject+/;
import core.sys.windows.windef /+: BOOL, DWORD+/;
import core.sys.windows.winerror /+: WAIT_TIMEOUT+/;

package enum isImplemented = true;

class Condition
{
    this( Mutex m ) nothrow @safe @nogc
    {
        this(m, true);
    }

    /// ditto
    this( shared Mutex m ) shared nothrow @safe @nogc
    {
        import core.atomic : atomicLoad;
        this(atomicLoad(m), true);
    }

    //
    private this(this Q, M)( M m, bool _unused_ ) nothrow @trusted @nogc
        if ((is(Q == Condition) && is(M == Mutex)) ||
            (is(Q == shared Condition) && is(M == shared Mutex)))
    {
        version (all)
        {
            static if (is(Q == Condition))
            {
                alias HANDLE_TYPE = void*;
            }
            else
            {
                alias HANDLE_TYPE = shared(void*);
            }
            m_blockLock = cast(HANDLE_TYPE) CreateSemaphoreA( null, 1, 1, null );
            if ( m_blockLock == m_blockLock.init )
                throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
            scope(failure) CloseHandle( cast(void*) m_blockLock );

            m_blockQueue = cast(HANDLE_TYPE) CreateSemaphoreA( null, 0, int.max, null );
            if ( m_blockQueue == m_blockQueue.init )
                throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
            scope(failure) CloseHandle( cast(void*) m_blockQueue );

            InitializeCriticalSection( cast(RTL_CRITICAL_SECTION*) &m_unblockLock );
            m_assocMutex = m;
        }
    }

    ~this() @nogc
    {
        version (all)
        {
            BOOL rc = CloseHandle( m_blockLock );
            assert( rc, "Unable to destroy condition" );
            rc = CloseHandle( m_blockQueue );
            assert( rc, "Unable to destroy condition" );
            DeleteCriticalSection( &m_unblockLock );
        }
    }


    ////////////////////////////////////////////////////////////////////////////
    // General Properties
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Gets the mutex associated with this condition.
     *
     * Returns:
     *  The mutex associated with this condition.
     */
    @property Mutex mutex()
    {
        return m_assocMutex;
    }

    /// ditto
    @property shared(Mutex) mutex() shared
    {
        import core.atomic : atomicLoad;
        return atomicLoad(m_assocMutex);
    }

    // undocumented function for internal use
    final @property Mutex mutex_nothrow() pure nothrow @safe @nogc
    {
        return m_assocMutex;
    }

    // ditto
    final @property shared(Mutex) mutex_nothrow() shared pure nothrow @safe @nogc
    {
        import core.atomic : atomicLoad;
        return atomicLoad(m_assocMutex);
    }

    ////////////////////////////////////////////////////////////////////////////
    // General Actions
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Wait until notified.
     *
     * Throws:
     *  SyncError on error.
     */
    void wait()
    {
        wait!(typeof(this))(true);
    }

    /// ditto
    void wait() shared
    {
        wait!(typeof(this))(true);
    }

    /// ditto
    void wait(this Q)( bool _unused_ )
        if (is(Q == Condition) || is(Q == shared Condition))
    {
        version (all)
        {
            timedWait( INFINITE );
        }
    }

    /**
     * Suspends the calling thread until a notification occurs or until the
     * supplied time period has elapsed.
     *
     * Params:
     *  val = The time to wait.
     *
     * In:
     *  val must be non-negative.
     *
     * Throws:
     *  SyncError on error.
     *
     * Returns:
     *  true if notified before the timeout and false if not.
     */
    bool wait( Duration val )
    {
        return wait!(typeof(this))(val, true);
    }

    /// ditto
    bool wait( Duration val ) shared
    {
        return wait!(typeof(this))(val, true);
    }

    /// ditto
    bool wait(this Q)( Duration val, bool _unused_ )
        if (is(Q == Condition) || is(Q == shared Condition))
    in
    {
        assert( !val.isNegative );
    }
    do
    {
        version (all)
        {
            auto maxWaitMillis = dur!("msecs")( uint.max - 1 );

            while ( val > maxWaitMillis )
            {
                if ( timedWait( cast(uint)
                               maxWaitMillis.total!"msecs" ) )
                    return true;
                val -= maxWaitMillis;
            }
            return timedWait( cast(uint) val.total!"msecs" );
        }
    }

    /**
     * Notifies one waiter.
     *
     * Throws:
     *  SyncError on error.
     */
    void notify()
    {
        notify!(typeof(this))(true);
    }

    /// ditto
    void notify() shared
    {
        notify!(typeof(this))(true);
    }

    /// ditto
    void notify(this Q)( bool _unused_ )
        if (is(Q == Condition) || is(Q == shared Condition))
    {
        version (all)
        {
            notify_( false );
        }
    }

    /**
     * Notifies all waiters.
     *
     * Throws:
     *  SyncError on error.
     */
    void notifyAll()
    {
        notifyAll!(typeof(this))(true);
    }

    /// ditto
    void notifyAll() shared
    {
        notifyAll!(typeof(this))(true);
    }

    /// ditto
    void notifyAll(this Q)( bool _unused_ )
        if (is(Q == Condition) || is(Q == shared Condition))
    {
        version (all)
        {
            notify_( true );
        }
    }

private:
    version (all)
    {
        bool timedWait(this Q)( DWORD timeout )
            if (is(Q == Condition) || is(Q == shared Condition))
        {
            static if (is(Q == Condition))
            {
                auto op(string o, T, V1)(ref T val, V1 mod)
                {
                    return mixin("val " ~ o ~ "mod");
                }
            }
            else
            {
                auto op(string o, T, V1)(ref shared T val, V1 mod)
                {
                    import core.atomic: atomicOp;
                    return atomicOp!o(val, mod);
                }
            }

            int   numSignalsLeft;
            int   numWaitersGone;
            DWORD rc;

            rc = WaitForSingleObject( cast(HANDLE) m_blockLock, INFINITE );
            assert( rc == WAIT_OBJECT_0 );

            op!"+="(m_numWaitersBlocked, 1);

            rc = ReleaseSemaphore( cast(HANDLE) m_blockLock, 1, null );
            assert( rc );

            m_assocMutex.unlock();
            scope(failure) m_assocMutex.lock();

            rc = WaitForSingleObject( cast(HANDLE) m_blockQueue, timeout );
            assert( rc == WAIT_OBJECT_0 || rc == WAIT_TIMEOUT );
            bool timedOut = (rc == WAIT_TIMEOUT);

            EnterCriticalSection( &m_unblockLock );
            scope(failure) LeaveCriticalSection( &m_unblockLock );

            if ( (numSignalsLeft = m_numWaitersToUnblock) != 0 )
            {
                if ( timedOut )
                {
                    // timeout (or canceled)
                    if ( m_numWaitersBlocked != 0 )
                    {
                        op!"-="(m_numWaitersBlocked, 1);
                        // do not unblock next waiter below (already unblocked)
                        numSignalsLeft = 0;
                    }
                    else
                    {
                        // spurious wakeup pending!!
                        m_numWaitersGone = 1;
                    }
                }
                if ( op!"-="(m_numWaitersToUnblock, 1) == 0 )
                {
                    if ( m_numWaitersBlocked != 0 )
                    {
                        // open the gate
                        rc = ReleaseSemaphore( cast(HANDLE) m_blockLock, 1, null );
                        assert( rc );
                        // do not open the gate below again
                        numSignalsLeft = 0;
                    }
                    else if ( (numWaitersGone = m_numWaitersGone) != 0 )
                    {
                        m_numWaitersGone = 0;
                    }
                }
            }
            else if ( op!"+="(m_numWaitersGone, 1) == int.max / 2 )
            {
                // timeout/canceled or spurious event :-)
                rc = WaitForSingleObject( cast(HANDLE) m_blockLock, INFINITE );
                assert( rc == WAIT_OBJECT_0 );
                // something is going on here - test of timeouts?
                op!"-="(m_numWaitersBlocked, m_numWaitersGone);
                rc = ReleaseSemaphore( cast(HANDLE) m_blockLock, 1, null );
                assert( rc == WAIT_OBJECT_0 );
                m_numWaitersGone = 0;
            }

            LeaveCriticalSection( &m_unblockLock );

            if ( numSignalsLeft == 1 )
            {
                // better now than spurious later (same as ResetEvent)
                for ( ; numWaitersGone > 0; --numWaitersGone )
                {
                    rc = WaitForSingleObject( cast(HANDLE) m_blockQueue, INFINITE );
                    assert( rc == WAIT_OBJECT_0 );
                }
                // open the gate
                rc = ReleaseSemaphore( cast(HANDLE) m_blockLock, 1, null );
                assert( rc );
            }
            else if ( numSignalsLeft != 0 )
            {
                // unblock next waiter
                rc = ReleaseSemaphore( cast(HANDLE) m_blockQueue, 1, null );
                assert( rc );
            }
            m_assocMutex.lock();
            return !timedOut;
        }


        void notify_(this Q)( bool all )
            if (is(Q == Condition) || is(Q == shared Condition))
        {
            static if (is(Q == Condition))
            {
                auto op(string o, T, V1)(ref T val, V1 mod)
                {
                    return mixin("val " ~ o ~ "mod");
                }
            }
            else
            {
                auto op(string o, T, V1)(ref shared T val, V1 mod)
                {
                    import core.atomic: atomicOp;
                    return atomicOp!o(val, mod);
                }
            }

            DWORD rc;

            EnterCriticalSection( &m_unblockLock );
            scope(failure) LeaveCriticalSection( &m_unblockLock );

            if ( m_numWaitersToUnblock != 0 )
            {
                if ( m_numWaitersBlocked == 0 )
                {
                    LeaveCriticalSection( &m_unblockLock );
                    return;
                }
                if ( all )
                {
                    op!"+="(m_numWaitersToUnblock, m_numWaitersBlocked);
                    m_numWaitersBlocked = 0;
                }
                else
                {
                    op!"+="(m_numWaitersToUnblock, 1);
                    op!"-="(m_numWaitersBlocked, 1);
                }
                LeaveCriticalSection( &m_unblockLock );
            }
            else if ( m_numWaitersBlocked > m_numWaitersGone )
            {
                rc = WaitForSingleObject( cast(HANDLE) m_blockLock, INFINITE );
                assert( rc == WAIT_OBJECT_0 );
                if ( 0 != m_numWaitersGone )
                {
                    op!"-="(m_numWaitersBlocked, m_numWaitersGone);
                    m_numWaitersGone = 0;
                }
                if ( all )
                {
                    m_numWaitersToUnblock = m_numWaitersBlocked;
                    m_numWaitersBlocked = 0;
                }
                else
                {
                    m_numWaitersToUnblock = 1;
                    op!"-="(m_numWaitersBlocked, 1);
                }
                LeaveCriticalSection( &m_unblockLock );
                rc = ReleaseSemaphore( cast(HANDLE) m_blockQueue, 1, null );
                assert( rc );
            }
            else
            {
                LeaveCriticalSection( &m_unblockLock );
            }
        }


        // NOTE: This implementation uses Algorithm 8c as described here:
        //       http://groups.google.com/group/comp.programming.threads/
        //              browse_frm/thread/1692bdec8040ba40/e7a5f9d40e86503a
        HANDLE              m_blockLock;    // auto-reset event (now semaphore)
        HANDLE              m_blockQueue;   // auto-reset event (now semaphore)
        Mutex               m_assocMutex;   // external mutex/CS
        CRITICAL_SECTION    m_unblockLock;  // internal mutex/CS
        int                 m_numWaitersGone        = 0;
        int                 m_numWaitersBlocked     = 0;
        int                 m_numWaitersToUnblock   = 0;
    }
}
