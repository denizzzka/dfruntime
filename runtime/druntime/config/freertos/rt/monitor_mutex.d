/**
 * FreeRTOS implementation for object monitors mutexes.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/rt/monitor_mutex.d)
 */
module rt.monitor_mutex;

package:
nothrow:
@nogc:

import internal.binding;
import core.exception;

private alias MonitorMutex = SemaphoreHandle_t;
alias Mutex = MonitorMutex;

void initMutex(MonitorMutex* mtx)
{
    *mtx = _xSemaphoreCreateMutex();

    if(*mtx is null)
        onOutOfMemoryError();
}

void destroyMutex(MonitorMutex* mtx)
{
    _vSemaphoreDelete(*mtx);
}

void lockMutex(MonitorMutex* mtx)
{
    if(xSemaphoreTake(*mtx, portMAX_DELAY) != pdTRUE)
        onInvalidMemoryOperationError();
}

void unlockMutex(MonitorMutex* mtx)
{
    if(_xSemaphoreGive(*mtx) != pdTRUE)
        onInvalidMemoryOperationError();
}

void initMutexesFacility() {}
void destroyMutexesFacility() {}
