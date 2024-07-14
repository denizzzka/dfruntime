/**
 * The semaphore module provides a general use semaphore for synchronization.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Sean Kelly
 * Source:    $(DRUNTIMESRC core/sync/_semaphore.d)
 */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sync.semaphore.impl;


import core.sync.exception;
import core.time;

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

version (Darwin)
{
    import core.sync.config;
    import core.stdc.errno;
    import core.sys.posix.time;
    import core.sys.darwin.mach.semaphore;
}
else
{
    import core.sync.config;
    import core.stdc.errno;
    import core.sys.posix.pthread;
    import core.sys.posix.semaphore;
}


////////////////////////////////////////////////////////////////////////////////
// Semaphore
//
// void wait();
// void notify();
// bool tryWait();
////////////////////////////////////////////////////////////////////////////////


/**
 * This class represents a general counting semaphore as concieved by Edsger
 * Dijkstra.  As per Mesa type monitors however, "signal" has been replaced
 * with "notify" to indicate that control is not transferred to the waiter when
 * a notification is sent.
 */
class Semaphore
{
    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Initializes a semaphore object with the specified initial count.
     *
     * Params:
     *  count = The initial count for the semaphore.
     *
     * Throws:
     *  SyncError on error.
     */
    this( uint count = 0 )
    {
        version (Darwin)
        {
            auto rc = semaphore_create( mach_task_self(), &m_hndl, SYNC_POLICY_FIFO, count );
            if ( rc )
                throw new SyncError( "Unable to create semaphore" );
        }
        else
        {
            int rc = sem_init( &m_hndl, 0, count );
            if ( rc )
                throw new SyncError( "Unable to create semaphore" );
        }
    }


    ~this()
    {
        version (Darwin)
        {
            auto rc = semaphore_destroy( mach_task_self(), m_hndl );
            assert( !rc, "Unable to destroy semaphore" );
        }
        else
        {
            int rc = sem_destroy( &m_hndl );
            assert( !rc, "Unable to destroy semaphore" );
        }
    }


    ////////////////////////////////////////////////////////////////////////////
    // General Actions
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Wait until the current count is above zero, then atomically decrement
     * the count by one and return.
     *
     * Throws:
     *  SyncError on error.
     */
    void wait()
    {
        version (Darwin)
        {
            while ( true )
            {
                auto rc = semaphore_wait( m_hndl );
                if ( !rc )
                    return;
                if ( rc == KERN_ABORTED && errno == EINTR )
                    continue;
                throw new SyncError( "Unable to wait for semaphore" );
            }
        }
        else
        {
            while ( true )
            {
                if ( !sem_wait( &m_hndl ) )
                    return;
                if ( errno != EINTR )
                    throw new SyncError( "Unable to wait for semaphore" );
            }
        }
    }


    /**
     * Suspends the calling thread until the current count moves above zero or
     * until the supplied time period has elapsed.  If the count moves above
     * zero in this interval, then atomically decrement the count by one and
     * return true.  Otherwise, return false.
     *
     * Params:
     *  period = The time to wait.
     *
     * In:
     *  period must be non-negative.
     *
     * Throws:
     *  SyncError on error.
     *
     * Returns:
     *  true if notified before the timeout and false if not.
     */
    bool wait( Duration period )
    in
    {
        assert( !period.isNegative );
    }
    do
    {
        version (Darwin)
        {
            mach_timespec_t t = void;
            (cast(byte*) &t)[0 .. t.sizeof] = 0;

            if ( period.total!"seconds" > t.tv_sec.max )
            {
                t.tv_sec  = t.tv_sec.max;
                t.tv_nsec = cast(typeof(t.tv_nsec)) period.split!("seconds", "nsecs")().nsecs;
            }
            else
                period.split!("seconds", "nsecs")(t.tv_sec, t.tv_nsec);
            while ( true )
            {
                auto rc = semaphore_timedwait( m_hndl, t );
                if ( !rc )
                    return true;
                if ( rc == KERN_OPERATION_TIMED_OUT )
                    return false;
                if ( rc != KERN_ABORTED || errno != EINTR )
                    throw new SyncError( "Unable to wait for semaphore" );
            }
        }
        else
        {
            import core.sys.posix.time : clock_gettime, CLOCK_REALTIME;

            timespec t = void;
            clock_gettime( CLOCK_REALTIME, &t );
            mvtspec( t, period );

            while ( true )
            {
                if ( !sem_timedwait( &m_hndl, &t ) )
                    return true;
                if ( errno == ETIMEDOUT )
                    return false;
                if ( errno != EINTR )
                    throw new SyncError( "Unable to wait for semaphore" );
            }
        }
    }


    /**
     * Atomically increment the current count by one.  This will notify one
     * waiter, if there are any in the queue.
     *
     * Throws:
     *  SyncError on error.
     */
    void notify()
    {
        version (Darwin)
        {
            auto rc = semaphore_signal( m_hndl );
            if ( rc )
                throw new SyncError( "Unable to notify semaphore" );
        }
        else
        {
            int rc = sem_post( &m_hndl );
            if ( rc )
                throw new SyncError( "Unable to notify semaphore" );
        }
    }


    /**
     * If the current count is equal to zero, return.  Otherwise, atomically
     * decrement the count by one and return true.
     *
     * Throws:
     *  SyncError on error.
     *
     * Returns:
     *  true if the count was above zero and false if not.
     */
    bool tryWait()
    {
        version (Darwin)
        {
            return wait( dur!"hnsecs"(0) );
        }
        else
        {
            while ( true )
            {
                if ( !sem_trywait( &m_hndl ) )
                    return true;
                if ( errno == EAGAIN )
                    return false;
                if ( errno != EINTR )
                    throw new SyncError( "Unable to wait for semaphore" );
            }
        }
    }


protected:

    /// Aliases the operating-system-specific semaphore type.
    version (Darwin)    alias Handle = semaphore_t;
    /// ditto
    else                alias Handle = sem_t;

    /// Handle to the system-specific semaphore.
    Handle m_hndl;
}
