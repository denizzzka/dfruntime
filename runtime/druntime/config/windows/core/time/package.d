//Written in the D programming language

/++
    Module containing core time functionality, such as $(LREF Duration) (which
    represents a duration of time) or $(LREF MonoTime) (which represents a
    timestamp of the system's monotonic clock).

    Various functions take a string (or strings) to represent a unit of time
    (e.g. $(D convert!("days", "hours")(numDays))). The valid strings to use
    with such functions are "years", "months", "weeks", "days", "hours",
    "minutes", "seconds", "msecs" (milliseconds), "usecs" (microseconds),
    "hnsecs" (hecto-nanoseconds - i.e. 100 ns) or some subset thereof. There
    are a few functions that also allow "nsecs", but very little actually
    has precision greater than hnsecs.

    $(BOOKTABLE Cheat Sheet,
    $(TR $(TH Symbol) $(TH Description))
    $(LEADINGROW Types)
    $(TR $(TDNW $(LREF Duration)) $(TD Represents a duration of time of weeks
    or less (kept internally as hnsecs). (e.g. 22 days or 700 seconds).))
    $(TR $(TDNW $(LREF TickDuration)) $(TD $(RED DEPRECATED) Represents a duration of time in
    system clock ticks, using the highest precision that the system provides.))
    $(TR $(TDNW $(LREF MonoTime)) $(TD Represents a monotonic timestamp in
    system clock ticks, using the highest precision that the system provides.))
    $(LEADINGROW Functions)
    $(TR $(TDNW $(LREF convert)) $(TD Generic way of converting between two time
    units.))
    $(TR $(TDNW $(LREF dur)) $(TD Allows constructing a $(LREF Duration) from
    the given time units with the given length.))
    $(TR $(TDNW $(LREF weeks)$(NBSP)$(LREF days)$(NBSP)$(LREF hours)$(BR)
    $(LREF minutes)$(NBSP)$(LREF seconds)$(NBSP)$(LREF msecs)$(BR)
    $(LREF usecs)$(NBSP)$(LREF hnsecs)$(NBSP)$(LREF nsecs))
    $(TD Convenience aliases for $(LREF dur).))
    $(TR $(TDNW $(LREF abs)) $(TD Returns the absolute value of a duration.))
    )

    $(BOOKTABLE Conversions,
    $(TR $(TH )
     $(TH From $(LREF Duration))
     $(TH From $(LREF TickDuration))
     $(TH From units)
    )
    $(TR $(TD $(B To $(LREF Duration)))
     $(TD -)
     $(TD $(D tickDuration.)$(REF_SHORT to, std,conv)$(D !Duration()))
     $(TD $(D dur!"msecs"(5)) or $(D 5.msecs()))
    )
    $(TR $(TD $(B To $(LREF TickDuration)))
     $(TD $(D duration.)$(REF_SHORT to, std,conv)$(D !TickDuration()))
     $(TD -)
     $(TD $(D TickDuration.from!"msecs"(msecs)))
    )
    $(TR $(TD $(B To units))
     $(TD $(D duration.total!"days"))
     $(TD $(D tickDuration.msecs))
     $(TD $(D convert!("days", "msecs")(msecs)))
    ))

    Copyright: Copyright 2010 - 2012
    License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   $(HTTP jmdavisprog.com, Jonathan M Davis) and Kato Shoichi
    Source:    $(DRUNTIMESRC core/_time.d)
    Macros:
    NBSP=&nbsp;
 +/
module core.time;

public import core.time.common;
import core.internal.string;

import core.sys.windows.winbase /+: QueryPerformanceCounter, QueryPerformanceFrequency+/;

//version (Windows)
enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    second = 6,
}

// This is called directly from the runtime initilization function (rt_init),
// instead of using a static constructor. Other subsystems inside the runtime
// (namely, the GC) may need time functionality, but cannot wait until the
// static ctors have run. Therefore, we initialize these specially. Because
// it's a normal function, we need to do some dangerous casting PLEASE take
// care when modifying this function, and it should NOT be called except from
// the runtime init.
//
// NOTE: the code below SPECIFICALLY does not assert when it cannot initialize
// the ticks per second array. This allows cases where a clock is never used on
// a system that doesn't support it. See bugzilla issue
// https://issues.dlang.org/show_bug.cgi?id=14863
// The assert will occur when someone attempts to use _ticksPerSecond for that
// value.
extern(C) void _d_initMonoTime() @nogc nothrow
{
    // We need a mutable pointer to the ticksPerSecond array. Although this
    // would appear to break immutability, it is logically the same as a static
    // ctor. So we should ONLY write these values once (we will check for 0
    // values when setting to ensure this is truly only called once).
    auto tps = cast(long[])_ticksPerSecond[];

    // If we try to do anything with ClockType in the documentation build, it'll
    // trigger the static assertions related to ClockType, since the
    // documentation build defines all of the possible ClockTypes, which won't
    // work when they're used in the static ifs, because no system supports them
    // all.
    version (CoreDdoc)
    {}
    else version (all)
    {
        long ticksPerSecond;
        if (QueryPerformanceFrequency(&ticksPerSecond) != 0)
        {
            foreach (i, typeStr; __traits(allMembers, ClockType))
            {
                // ensure we are only writing immutable data once
                if (tps[i] != 0)
                    // should only be called once
                    assert(0);
                tps[i] = ticksPerSecond;
            }
        }
    }
}

version (CoreUnittest) deprecated
{
    package @property TickDuration currSystemTick() @trusted nothrow @nogc
    {
        import core.internal.abort : abort;
        version (all)
        {
            ulong ticks = void;
            QueryPerformanceCounter(cast(long*)&ticks);
            return TickDuration(ticks);
        }
    }
}

deprecated package long getTicksPerSec()
{
    import core.sys.windows.winbase: QueryPerformanceFrequency;

    long ticksPerSec;

    if (QueryPerformanceFrequency(&ticksPerSec) == 0)
        ticksPerSec = 0;

    return ticksPerSec;
}

package long getCurrMonoTime(MT, alias ClockType clockType)() @trusted nothrow @nogc
{
    long ticks = void;
    QueryPerformanceCounter(&ticks);
    return ticks;
}
