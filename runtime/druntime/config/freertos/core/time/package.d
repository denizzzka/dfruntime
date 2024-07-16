module core.time;

public import core.time.common;

long currTicks() @trusted nothrow @nogc
{
    return os.xTaskGetTickCount();
}

package:

enum ClockType
{
    normal = 0,
    //~ coarse = 2,
    //~ precise = 3,
    second = 6, //TODO: used only for druntime core unittest, do something with this
}

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
