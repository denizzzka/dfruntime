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
module core.sync.semaphore;


public import core.sync.exception;
public import core.time;

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
public import core.sync.semaphore.impl: Semaphore;

////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////

version(ThreadsDisabled) {} else
unittest
{
    import core.thread, core.atomic;

    void testWait()
    {
        auto semaphore = new Semaphore;
        shared bool stopConsumption = false;
        immutable numToProduce = 20;
        immutable numConsumers = 10;
        shared size_t numConsumed;
        shared size_t numComplete;

        void consumer()
        {
            while (true)
            {
                semaphore.wait();

                if (atomicLoad(stopConsumption))
                    break;
                atomicOp!"+="(numConsumed, 1);
            }
            atomicOp!"+="(numComplete, 1);
        }

        void producer()
        {
            assert(!semaphore.tryWait());

            foreach (_; 0 .. numToProduce)
                semaphore.notify();

            // wait until all items are consumed
            while (atomicLoad(numConsumed) != numToProduce)
                Thread.yield();

            // mark consumption as finished
            atomicStore(stopConsumption, true);

            // wake all consumers
            foreach (_; 0 .. numConsumers)
                semaphore.notify();

            // wait until all consumers completed
            while (atomicLoad(numComplete) != numConsumers)
                Thread.yield();

            assert(!semaphore.tryWait());
            semaphore.notify();
            assert(semaphore.tryWait());
            assert(!semaphore.tryWait());
        }

        auto group = new ThreadGroup;

        for ( int i = 0; i < numConsumers; ++i )
            group.create(&consumer);
        group.create(&producer);
        group.joinAll();
    }


    void testWaitTimeout()
    {
        auto sem = new Semaphore;
        shared bool semReady;
        bool alertedOne, alertedTwo;

        void waiter()
        {
            while (!atomicLoad(semReady))
                Thread.yield();
            alertedOne = sem.wait(dur!"msecs"(1));
            alertedTwo = sem.wait(dur!"msecs"(1));
            assert(alertedOne && !alertedTwo);
        }

        auto thread = new Thread(&waiter);
        thread.start();

        sem.notify();
        atomicStore(semReady, true);
        thread.join();
        assert(alertedOne && !alertedTwo);
    }

    testWait();
    testWaitTimeout();
}
