/**
 * This module provides types and constants used in thread package.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/core/thread/types.d)
 */
module core.thread.types;

import internal.binding /*freertos_binding*/ : TaskHandle_t;
public import core.thread.stack: isStackGrowingDown;

alias ThreadID = TaskHandle_t;

struct ll_ThreadData
{
    //TODO: move to EventAwaiter
    import core.sync.event: Event;
    import core.atomic;

    ThreadID tid;
    Event joinEvent;
    private shared size_t joinEventSubscribersNum;

    void initialize() nothrow @nogc
    {
        joinEvent.initialize(true, false);
    }

    auto getSubscribersNum()
    {
        return atomicLoad(joinEventSubscribersNum);
    }

    void deletionLock() @nogc nothrow
    {
        joinEventSubscribersNum.atomicOp!"+="(1);
    }

    void deletionUnlock() @nogc nothrow
    {
        joinEventSubscribersNum.atomicOp!"-="(1);
    }
}

unittest
{
    ll_ThreadData td;
    td.initialize();

    assert(td.getSubscribersNum() == 0);
    td.deletionLock();
    assert(td.getSubscribersNum() == 1);
    td.deletionLock();
    assert(td.getSubscribersNum() == 2);
    td.deletionUnlock();
    assert(td.getSubscribersNum() == 1);
    td.deletionUnlock();
    assert(td.getSubscribersNum() == 0);
}
