/**
 * FreeRTOS core.time implementation
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/core/time/package.d)
 */
module core.time;

public import core.time.common;

long currTicks() @trusted nothrow @nogc
{
    return os.xTaskGetTickCount();
}

enum ClockType
{
    normal = 0,
    //~ coarse = 2,
    //~ precise = 3,
    second = 6, //TODO: used only for druntime core unittest, do something with this
}

package:

import core.time;

//FIXME: TickDuration is deprecated!
deprecated
static @property TickDuration currSystemTick() @trusted nothrow @nogc
{
    return TickDuration(currTicks);
}

static import os = internal.binding; //FIXME: rename module to freertos_binding

package long getCurrMonoTime(MT, alias ClockType clockType)() @trusted nothrow @nogc
{
    return currTicks();
}

//TODO: templatize this calculations to avoid wasting CPU time
public uint toTicks(Duration d) @safe nothrow @nogc pure
in(_ticksPerSec >= 1000)
{
    long r = _ticksPerSec / 1000 * d.total!"msecs";

    assert(r <= uint.max);

    return cast(uint) r;
}

unittest
{
    assert(1.seconds.toTicks == _ticksPerSec);
}

private enum _ticksPerSec = os.configTICK_RATE_HZ;

long getTicksPerSec()
{
    return _ticksPerSec;
}
