/**
 * FreeRTOS semaphore module provides a general use semaphore for synchronization.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/core/sync/semaphore/impl.d)
 */
module core.sync.semaphore.impl;

static import os = internal.binding;
import core.exception: onOutOfMemoryError;
import core.stdc.errno;
import core.sync.exception: SyncError;
import core.time: toTicks;

class Semaphore
{
    private os.SemaphoreHandle_t m_hndl;

    this(size_t initialCount = 0) nothrow @nogc
    {
        import core.stdc.config: c_long;

        m_hndl = os.xSemaphoreCreateCounting(c_long.max /* c_ulong */, initialCount);

        if(!m_hndl)
            onOutOfMemoryError();
    }

    ~this() nothrow @nogc
    {
        os._vSemaphoreDelete(m_hndl);

        debug m_hndl = null;
    }

    void wait()
    {
        if(!waitOrError())
            throw new SyncError("Unable to wait for semaphore");
    }

    bool waitOrError() nothrow @nogc
    {
        return os.xSemaphoreTake(m_hndl, os.portMAX_DELAY) == os.pdTRUE;
    }

    import core.time;

    bool wait(Duration period)
    in(!period.isNegative)
    {
        return os.xSemaphoreTake(m_hndl, period.toTicks) == os.pdTRUE;
    }

    bool tryWait() nothrow @nogc
    {
        return os.xSemaphoreTake(m_hndl, 0) == os.pdTRUE;
    }

    void notify()
    {
        if(!notifyOrError())
            throw new SyncError("Unable to notify semaphore");
    }

    bool notifyOrError() nothrow @nogc
    {
        return os._xSemaphoreGive(m_hndl) == os.pdTRUE;
    }
}
