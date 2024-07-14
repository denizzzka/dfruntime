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
module core.sync.condition;


public import core.sync.exception;
public import core.sync.mutex;
public import core.time;

import core.exception : AssertError, staticError;


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
public import core.sync.condition.impl: Condition, isImplemented;

////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////

// Condition is difficult to implement and is isn't used by druntime itself
// Therefore it can be disabled if backend isn't provides it
static if(isImplemented)
unittest
{
    import core.thread;
    import core.sync.mutex;
    import core.sync.semaphore;


    void testNotify()
    {
        auto mutex      = new Mutex;
        auto condReady  = new Condition( mutex );
        auto semDone    = new Semaphore;
        auto synLoop    = new Object;
        int  numWaiters = 10;
        int  numTries   = 10;
        int  numReady   = 0;
        int  numTotal   = 0;
        int  numDone    = 0;
        int  numPost    = 0;

        void waiter()
        {
            for ( int i = 0; i < numTries; ++i )
            {
                synchronized( mutex )
                {
                    while ( numReady < 1 )
                    {
                        condReady.wait();
                    }
                    --numReady;
                    ++numTotal;
                }

                synchronized( synLoop )
                {
                    ++numDone;
                }
                semDone.wait();
            }
        }

        auto group = new ThreadGroup;

        for ( int i = 0; i < numWaiters; ++i )
            group.create( &waiter );

        for ( int i = 0; i < numTries; ++i )
        {
            for ( int j = 0; j < numWaiters; ++j )
            {
                synchronized( mutex )
                {
                    ++numReady;
                    condReady.notify();
                }
            }
            while ( true )
            {
                synchronized( synLoop )
                {
                    if ( numDone >= numWaiters )
                        break;
                }
                Thread.yield();
            }
            for ( int j = 0; j < numWaiters; ++j )
            {
                semDone.notify();
            }
        }

        group.joinAll();
        assert( numTotal == numWaiters * numTries );
    }


    void testNotifyAll()
    {
        auto mutex      = new Mutex;
        auto condReady  = new Condition( mutex );
        int  numWaiters = 10;
        int  numReady   = 0;
        int  numDone    = 0;
        bool alert      = false;

        void waiter()
        {
            synchronized( mutex )
            {
                ++numReady;
                while ( !alert )
                    condReady.wait();
                ++numDone;
            }
        }

        auto group = new ThreadGroup;

        for ( int i = 0; i < numWaiters; ++i )
            group.create( &waiter );

        while ( true )
        {
            synchronized( mutex )
            {
                if ( numReady >= numWaiters )
                {
                    alert = true;
                    condReady.notifyAll();
                    break;
                }
            }
            Thread.yield();
        }
        group.joinAll();
        assert( numReady == numWaiters && numDone == numWaiters );
    }


    void testWaitTimeout()
    {
        auto mutex      = new Mutex;
        auto condReady  = new Condition( mutex );
        bool waiting    = false;
        bool alertedOne = true;
        bool alertedTwo = true;

        void waiter()
        {
            synchronized( mutex )
            {
                waiting    = true;
                // we never want to miss the notification (30s)
                alertedOne = condReady.wait( dur!"seconds"(30) );
                // but we don't want to wait long for the timeout (10ms)
                alertedTwo = condReady.wait( dur!"msecs"(10) );
            }
        }

        auto thread = new Thread( &waiter );
        thread.start();

        while ( true )
        {
            synchronized( mutex )
            {
                if ( waiting )
                {
                    condReady.notify();
                    break;
                }
            }
            Thread.yield();
        }
        thread.join();
        assert( waiting );
        assert( alertedOne );
        assert( !alertedTwo );
    }

    testNotify();
    testNotifyAll();
    testWaitTimeout();
}

unittest
{
    import core.thread;
    import core.sync.mutex;
    import core.sync.semaphore;


    void testNotify()
    {
        auto mutex      = new shared Mutex;
        auto condReady  = new shared Condition( mutex );
        auto semDone    = new Semaphore;
        auto synLoop    = new Object;
        int  numWaiters = 10;
        int  numTries   = 10;
        int  numReady   = 0;
        int  numTotal   = 0;
        int  numDone    = 0;
        int  numPost    = 0;

        void waiter()
        {
            for ( int i = 0; i < numTries; ++i )
            {
                synchronized( mutex )
                {
                    while ( numReady < 1 )
                    {
                        condReady.wait();
                    }
                    --numReady;
                    ++numTotal;
                }

                synchronized( synLoop )
                {
                    ++numDone;
                }
                semDone.wait();
            }
        }

        auto group = new ThreadGroup;

        for ( int i = 0; i < numWaiters; ++i )
            group.create( &waiter );

        for ( int i = 0; i < numTries; ++i )
        {
            for ( int j = 0; j < numWaiters; ++j )
            {
                synchronized( mutex )
                {
                    ++numReady;
                    condReady.notify();
                }
            }
            while ( true )
            {
                synchronized( synLoop )
                {
                    if ( numDone >= numWaiters )
                        break;
                }
                Thread.yield();
            }
            for ( int j = 0; j < numWaiters; ++j )
            {
                semDone.notify();
            }
        }

        group.joinAll();
        assert( numTotal == numWaiters * numTries );
    }


    void testNotifyAll()
    {
        auto mutex      = new shared Mutex;
        auto condReady  = new shared Condition( mutex );
        int  numWaiters = 10;
        int  numReady   = 0;
        int  numDone    = 0;
        bool alert      = false;

        void waiter()
        {
            synchronized( mutex )
            {
                ++numReady;
                while ( !alert )
                    condReady.wait();
                ++numDone;
            }
        }

        auto group = new ThreadGroup;

        for ( int i = 0; i < numWaiters; ++i )
            group.create( &waiter );

        while ( true )
        {
            synchronized( mutex )
            {
                if ( numReady >= numWaiters )
                {
                    alert = true;
                    condReady.notifyAll();
                    break;
                }
            }
            Thread.yield();
        }
        group.joinAll();
        assert( numReady == numWaiters && numDone == numWaiters );
    }


    void testWaitTimeout()
    {
        auto mutex      = new shared Mutex;
        auto condReady  = new shared Condition( mutex );
        bool waiting    = false;
        bool alertedOne = true;
        bool alertedTwo = true;

        void waiter()
        {
            synchronized( mutex )
            {
                waiting    = true;
                // we never want to miss the notification (30s)
                alertedOne = condReady.wait( dur!"seconds"(30) );
                // but we don't want to wait long for the timeout (10ms)
                alertedTwo = condReady.wait( dur!"msecs"(10) );
            }
        }

        auto thread = new Thread( &waiter );
        thread.start();

        while ( true )
        {
            synchronized( mutex )
            {
                if ( waiting )
                {
                    condReady.notify();
                    break;
                }
            }
            Thread.yield();
        }
        thread.join();
        assert( waiting );
        assert( alertedOne );
        assert( !alertedTwo );
    }

    testNotify();
    testNotifyAll();
    testWaitTimeout();
}
