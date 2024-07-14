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

import core.sync.config;
import core.stdc.errno;
import core.sys.posix.pthread;
import core.sys.posix.time;

package enum isImplemented = true;

////////////////////////////////////////////////////////////////////////////////
// Condition
//
// void wait();
// void notify();
// void notifyAll();
////////////////////////////////////////////////////////////////////////////////

/**
 * This class represents a condition variable as conceived by C.A.R. Hoare.  As
 * per Mesa type monitors however, "signal" has been replaced with "notify" to
 * indicate that control is not transferred to the waiter when a notification
 * is sent.
 */
class Condition
{
    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////

    /**
     * Initializes a condition object which is associated with the supplied
     * mutex object.
     *
     * Params:
     *  m = The mutex with which this condition will be associated.
     *
     * Throws:
     *  SyncError on error.
     */
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
            static if (is(Q == shared))
            {
                import core.atomic : atomicLoad;
                m_assocMutex = atomicLoad(m);
            }
            else
            {
                m_assocMutex = m;
            }
            static if ( is( typeof( pthread_condattr_setclock ) ) )
            {
                () @trusted
                {
                    pthread_condattr_t attr = void;
                    int rc  = pthread_condattr_init( &attr );
                    if ( rc )
                        throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
                    rc = pthread_condattr_setclock( &attr, CLOCK_MONOTONIC );
                    if ( rc )
                        throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
                    rc = pthread_cond_init( cast(pthread_cond_t*) &m_hndl, &attr );
                    if ( rc )
                        throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
                    rc = pthread_condattr_destroy( &attr );
                    if ( rc )
                        throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
                } ();
            }
            else
            {
                int rc = pthread_cond_init( cast(pthread_cond_t*) &m_hndl, null );
                if ( rc )
                    throw staticError!AssertError("Unable to initialize condition", __FILE__, __LINE__);
            }
        }
    }

    ~this() @nogc
    {
        version (all)
        {
            int rc = pthread_cond_destroy( &m_hndl );
            assert( !rc, "Unable to destroy condition" );
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
            int rc = pthread_cond_wait( cast(pthread_cond_t*) &m_hndl, (cast(Mutex) m_assocMutex).handleAddr() );
            if ( rc )
                throw staticError!AssertError("Unable to wait for condition", __FILE__, __LINE__);
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
            timespec t = void;
            mktspec( t, val );

            int rc = pthread_cond_timedwait( cast(pthread_cond_t*) &m_hndl,
                                             (cast(Mutex) m_assocMutex).handleAddr(),
                                             &t );
            if ( !rc )
                return true;
            if ( rc == ETIMEDOUT )
                return false;
            throw staticError!AssertError("Unable to wait for condition", __FILE__, __LINE__);
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
            // Since OS X 10.7 (Lion), pthread_cond_signal returns EAGAIN after retrying 8192 times,
            // so need to retrying while it returns EAGAIN.
            //
            // 10.7.0 (Lion):          http://www.opensource.apple.com/source/Libc/Libc-763.11/pthreads/pthread_cond.c
            // 10.8.0 (Mountain Lion): http://www.opensource.apple.com/source/Libc/Libc-825.24/pthreads/pthread_cond.c
            // 10.10.0 (Yosemite):     http://www.opensource.apple.com/source/libpthread/libpthread-105.1.4/src/pthread_cond.c
            // 10.11.0 (El Capitan):   http://www.opensource.apple.com/source/libpthread/libpthread-137.1.1/src/pthread_cond.c
            // 10.12.0 (Sierra):       http://www.opensource.apple.com/source/libpthread/libpthread-218.1.3/src/pthread_cond.c
            // 10.13.0 (High Sierra):  http://www.opensource.apple.com/source/libpthread/libpthread-301.1.6/src/pthread_cond.c
            // 10.14.0 (Mojave):       http://www.opensource.apple.com/source/libpthread/libpthread-330.201.1/src/pthread_cond.c
            // 10.14.1 (Mojave):       http://www.opensource.apple.com/source/libpthread/libpthread-330.220.2/src/pthread_cond.c

            int rc;
            do {
                rc = pthread_cond_signal( cast(pthread_cond_t*) &m_hndl );
            } while ( rc == EAGAIN );
            if ( rc )
                throw staticError!AssertError("Unable to notify condition", __FILE__, __LINE__);
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
            // Since OS X 10.7 (Lion), pthread_cond_broadcast returns EAGAIN after retrying 8192 times,
            // so need to retrying while it returns EAGAIN.
            //
            // 10.7.0 (Lion):          http://www.opensource.apple.com/source/Libc/Libc-763.11/pthreads/pthread_cond.c
            // 10.8.0 (Mountain Lion): http://www.opensource.apple.com/source/Libc/Libc-825.24/pthreads/pthread_cond.c
            // 10.10.0 (Yosemite):     http://www.opensource.apple.com/source/libpthread/libpthread-105.1.4/src/pthread_cond.c
            // 10.11.0 (El Capitan):   http://www.opensource.apple.com/source/libpthread/libpthread-137.1.1/src/pthread_cond.c
            // 10.12.0 (Sierra):       http://www.opensource.apple.com/source/libpthread/libpthread-218.1.3/src/pthread_cond.c
            // 10.13.0 (High Sierra):  http://www.opensource.apple.com/source/libpthread/libpthread-301.1.6/src/pthread_cond.c
            // 10.14.0 (Mojave):       http://www.opensource.apple.com/source/libpthread/libpthread-330.201.1/src/pthread_cond.c
            // 10.14.1 (Mojave):       http://www.opensource.apple.com/source/libpthread/libpthread-330.220.2/src/pthread_cond.c

            int rc;
            do {
                rc = pthread_cond_broadcast( cast(pthread_cond_t*) &m_hndl );
            } while ( rc == EAGAIN );
            if ( rc )
                throw staticError!AssertError("Unable to notify condition", __FILE__, __LINE__);
        }
    }

private:
    version (all)
    {
        Mutex               m_assocMutex;
        pthread_cond_t      m_hndl;
    }
}
