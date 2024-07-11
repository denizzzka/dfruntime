module core.stdc.time_impl;

enum ClockType
{
    normal = 0,
    //~ coarse = 2,
    //~ precise = 3,
    second = 6, //TODO: used only for druntime core unittest, do something with this
}

import core.stdc.config: c_long;
alias time_t = c_long;

// add ability to import tm from core.sys.posix.stdc.time
struct tm
{
    int     tm_sec;     /// seconds after the minute [0-60]
    int     tm_min;     /// minutes after the hour [0-59]
    int     tm_hour;    /// hours since midnight [0-23]
    int     tm_mday;    /// day of the month [1-31]
    int     tm_mon;     /// months since January [0-11]
    int     tm_year;    /// years since 1900
    int     tm_wday;    /// days since Sunday [0-6]
    int     tm_yday;    /// days since January 1 [0-365]
    int     tm_isdst;   /// Daylight Savings Time flag
    c_long  tm_gmtoff;  /// offset from CUT in seconds
    char*   tm_zone;    /// timezone abbreviation
}

import core.time;

//FIXME: TickDuration is deprecated!
static @property TickDuration currSystemTick() @trusted nothrow @nogc
{
    return TickDuration(currTicks);
}

static import os = freertos_binding;

long currTicks() @trusted nothrow @nogc
{
    return os.xTaskGetTickCount();
}

//TODO: templatize this calculations to avoid wasting CPU time
uint toTicks(Duration d) @safe nothrow @nogc pure
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

enum _ticksPerSec = os.configTICK_RATE_HZ;

void initTicksPerSecond(ref long[] tps) @nogc nothrow
{
    tps[0] = _ticksPerSec; // ClockType.normal
}

// Linked by picolibc
struct timeval {
    long    tv_sec;     /* seconds */
    long    tv_usec;    /* and microseconds */
}

extern(C) int gettimeofday(timeval* tv, void*) // timezone_t* is normally void*
{
    //FIXME
    tv.tv_sec = 123;
    tv.tv_usec = 456;

    return 0;
}
