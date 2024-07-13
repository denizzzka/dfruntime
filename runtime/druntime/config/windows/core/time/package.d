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

/++
    Represents a timestamp of the system's monotonic clock.

    A monotonic clock is one which always goes forward and never moves
    backwards, unlike the system's wall clock time (as represented by
    $(REF SysTime, std,datetime)). The system's wall clock time can be adjusted
    by the user or by the system itself via services such as NTP, so it is
    unreliable to use the wall clock time for timing. Timers which use the wall
    clock time could easily end up never going off due to changes made to the
    wall clock time or otherwise waiting for a different period of time than
    that specified by the programmer. However, because the monotonic clock
    always increases at a fixed rate and is not affected by adjustments to the
    wall clock time, it is ideal for use with timers or anything which requires
    high precision timing.

    So, MonoTime should be used for anything involving timers and timing,
    whereas $(REF SysTime, std,datetime) should be used when the wall clock time
    is required.

    The monotonic clock has no relation to wall clock time. Rather, it holds
    its time as the number of ticks of the clock which have occurred since the
    clock started (typically when the system booted up). So, to determine how
    much time has passed between two points in time, one monotonic time is
    subtracted from the other to determine the number of ticks which occurred
    between the two points of time, and those ticks are divided by the number of
    ticks that occur every second (as represented by MonoTime.ticksPerSecond)
    to get a meaningful duration of time. Normally, MonoTime does these
    calculations for the programmer, but the $(D ticks) and $(D ticksPerSecond)
    properties are provided for those who require direct access to the system
    ticks. The normal way that MonoTime would be used is

--------------------
    MonoTime before = MonoTime.currTime;
    // do stuff...
    MonoTime after = MonoTime.currTime;
    Duration timeElapsed = after - before;
--------------------

    $(LREF MonoTime) is an alias to $(D MonoTimeImpl!(ClockType.normal)) and is
    what most programs should use for the monotonic clock, so that's what is
    used in most of $(D MonoTimeImpl)'s documentation. But $(D MonoTimeImpl)
    can be instantiated with other clock types for those rare programs that need
    it.

    See_Also:
        $(LREF ClockType)
  +/
struct MonoTimeImpl(ClockType clockType)
{
    private enum _clockIdx = _clockTypeIdx(clockType);
    private enum _clockName = _clockTypeName(clockType);

@safe:

    version (all)
    {
        static if (clockType != ClockType.coarse &&
                  clockType != ClockType.normal &&
                  clockType != ClockType.precise)
        {
            static assert(0, "ClockType." ~ _clockName ~
                             " is not supported by MonoTimeImpl on this system.");
        }
    }

    // POD value, test mutable/const/immutable conversion
    version (CoreUnittest) unittest
    {
        MonoTimeImpl m;
        const MonoTimeImpl cm = m;
        immutable MonoTimeImpl im = m;
        m = cm;
        m = im;
    }

    /++
        The current time of the system's monotonic clock. This has no relation
        to the wall clock time, as the wall clock time can be adjusted (e.g.
        by NTP), whereas the monotonic clock always moves forward. The source
        of the monotonic time is system-specific.

        On Windows, $(D QueryPerformanceCounter) is used. On Mac OS X,
        $(D mach_absolute_time) is used, while on other POSIX systems,
        $(D clock_gettime) is used.

        $(RED Warning): On some systems, the monotonic clock may stop counting
                        when the computer goes to sleep or hibernates. So, the
                        monotonic clock may indicate less time than has actually
                        passed if that occurs. This is known to happen on
                        Mac OS X. It has not been tested whether it occurs on
                        either Windows or Linux.
      +/
    static @property MonoTimeImpl currTime() @trusted nothrow @nogc
    {
        if (ticksPerSecond == 0)
        {
            import core.internal.abort : abort;
            abort("MonoTimeImpl!(ClockType." ~ _clockName ~
                      ") failed to get the frequency of the system's monotonic clock.");
        }

        version (Windows)
        {
            long ticks = void;
            QueryPerformanceCounter(&ticks);
            return MonoTimeImpl(ticks);
        }
        else version (Darwin)
            return MonoTimeImpl(mach_absolute_time());
        else version (Posix)
        {
            timespec ts = void;
            immutable error = clock_gettime(clockArg, &ts);
            // clockArg is supported and if tv_sec is long or larger
            // overflow won't happen before 292 billion years A.D.
            static if (ts.tv_sec.max < long.max)
            {
                if (error)
                {
                    import core.internal.abort : abort;
                    abort("Call to clock_gettime failed.");
                }
            }
            return MonoTimeImpl(convClockFreq(ts.tv_sec * 1_000_000_000L + ts.tv_nsec,
                                              1_000_000_000L,
                                              ticksPerSecond));
        }
        else version (DruntimeAbstractRt)
        {
            import external.core.time : currTicks;

            return MonoTimeImpl(currTicks);
        }
    }


    static @property pure nothrow @nogc
    {
    /++
        A $(D MonoTime) of $(D 0) ticks. It's provided to be consistent with
        $(D Duration.zero), and it's more explicit than $(D MonoTime.init).
      +/
    MonoTimeImpl zero() { return MonoTimeImpl(0); }

    /++
        Largest $(D MonoTime) possible.
      +/
    MonoTimeImpl max() { return MonoTimeImpl(long.max); }

    /++
        Most negative $(D MonoTime) possible.
      +/
    MonoTimeImpl min() { return MonoTimeImpl(long.min); }
    }

    version (CoreUnittest) unittest
    {
        assert(MonoTimeImpl.zero == MonoTimeImpl(0));
        assert(MonoTimeImpl.max == MonoTimeImpl(long.max));
        assert(MonoTimeImpl.min == MonoTimeImpl(long.min));
        assert(MonoTimeImpl.min < MonoTimeImpl.zero);
        assert(MonoTimeImpl.zero < MonoTimeImpl.max);
        assert(MonoTimeImpl.min < MonoTimeImpl.max);
    }


    /++
        Compares this MonoTime with the given MonoTime.

        Returns:
            $(BOOKTABLE,
                $(TR $(TD this &lt; rhs) $(TD &lt; 0))
                $(TR $(TD this == rhs) $(TD 0))
                $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(MonoTimeImpl rhs) const pure nothrow @nogc
    {
        return (_ticks > rhs._ticks) - (_ticks < rhs._ticks);
    }

    version (CoreUnittest) unittest
    {
        import core.internal.traits : rvalueOf;
        const t = MonoTimeImpl.currTime;
        assert(t == rvalueOf(t));
    }

    version (CoreUnittest) unittest
    {
        import core.internal.traits : rvalueOf;
        const before = MonoTimeImpl.currTime;
        auto after = MonoTimeImpl(before._ticks + 42);
        assert(before < after);
        assert(rvalueOf(before) <= before);
        assert(rvalueOf(after) > before);
        assert(after >= rvalueOf(after));
    }

    version (CoreUnittest) unittest
    {
        const currTime = MonoTimeImpl.currTime;
        assert(MonoTimeImpl(long.max) > MonoTimeImpl(0));
        assert(MonoTimeImpl(0) > MonoTimeImpl(long.min));
        assert(MonoTimeImpl(long.max) > currTime);
        assert(currTime > MonoTimeImpl(0));
        assert(MonoTimeImpl(0) < currTime);
        assert(MonoTimeImpl(0) < MonoTimeImpl(long.max));
        assert(MonoTimeImpl(long.min) < MonoTimeImpl(0));
    }


    /++
        Subtracting two MonoTimes results in a $(LREF Duration) representing
        the amount of time which elapsed between them.

        The primary way that programs should time how long something takes is to
        do
--------------------
MonoTime before = MonoTime.currTime;
// do stuff
MonoTime after = MonoTime.currTime;

// How long it took.
Duration timeElapsed = after - before;
--------------------
        or to use a wrapper (such as a stop watch type) which does that.

        $(RED Warning):
            Because $(LREF Duration) is in hnsecs, whereas MonoTime is in system
            ticks, it's usually the case that this assertion will fail
--------------------
auto before = MonoTime.currTime;
// do stuff
auto after = MonoTime.currTime;
auto timeElapsed = after - before;
assert(before + timeElapsed == after);
--------------------

            This is generally fine, and by its very nature, converting from
            system ticks to any type of seconds (hnsecs, nsecs, etc.) will
            introduce rounding errors, but if code needs to avoid any of the
            small rounding errors introduced by conversion, then it needs to use
            MonoTime's $(D ticks) property and keep all calculations in ticks
            rather than using $(LREF Duration).
      +/
    Duration opBinary(string op)(MonoTimeImpl rhs) const pure nothrow @nogc
        if (op == "-")
    {
        immutable diff = _ticks - rhs._ticks;
        return Duration(convClockFreq(diff , ticksPerSecond, hnsecsPer!"seconds"));
    }

    version (CoreUnittest) unittest
    {
        import core.internal.traits : rvalueOf;
        const t = MonoTimeImpl.currTime;
        assert(t - rvalueOf(t) == Duration.zero);
        static assert(!__traits(compiles, t + t));
    }

    version (CoreUnittest) unittest
    {
        static void test(const scope MonoTimeImpl before, const scope MonoTimeImpl after, const scope Duration min)
        {
            immutable diff = after - before;
            assert(diff >= min);
            auto calcAfter = before + diff;
            assertApprox(calcAfter, calcAfter - Duration(1), calcAfter + Duration(1));
            assert(before - after == -diff);
        }

        const before = MonoTimeImpl.currTime;
        test(before, MonoTimeImpl(before._ticks + 4202), Duration.zero);
        test(before, MonoTimeImpl.currTime, Duration.zero);

        const durLargerUnits = dur!"minutes"(7) + dur!"seconds"(22);
        test(before, before + durLargerUnits + dur!"msecs"(33) + dur!"hnsecs"(571), durLargerUnits);
    }


    /++
        Adding or subtracting a $(LREF Duration) to/from a MonoTime results in
        a MonoTime which is adjusted by that amount.
      +/
    MonoTimeImpl opBinary(string op)(Duration rhs) const pure nothrow @nogc
        if (op == "+" || op == "-")
    {
        immutable rhsConverted = convClockFreq(rhs._hnsecs, hnsecsPer!"seconds", ticksPerSecond);
        mixin("return MonoTimeImpl(_ticks " ~ op ~ " rhsConverted);");
    }

    version (CoreUnittest) unittest
    {
        const t = MonoTimeImpl.currTime;
        assert(t + Duration(0) == t);
        assert(t - Duration(0) == t);
    }

    version (CoreUnittest) unittest
    {
        const t = MonoTimeImpl.currTime;

        // We reassign ticks in order to get the same rounding errors
        // that we should be getting with Duration (e.g. MonoTimeImpl may be
        // at a higher precision than hnsecs, meaning that 7333 would be
        // truncated when converting to hnsecs).
        long ticks = 7333;
        auto hnsecs = convClockFreq(ticks, ticksPerSecond, hnsecsPer!"seconds");
        ticks = convClockFreq(hnsecs, hnsecsPer!"seconds", ticksPerSecond);

        assert(t - Duration(hnsecs) == MonoTimeImpl(t._ticks - ticks));
        assert(t + Duration(hnsecs) == MonoTimeImpl(t._ticks + ticks));
    }


    /++ Ditto +/
    ref MonoTimeImpl opOpAssign(string op)(Duration rhs) pure nothrow @nogc
        if (op == "+" || op == "-")
    {
        immutable rhsConverted = convClockFreq(rhs._hnsecs, hnsecsPer!"seconds", ticksPerSecond);
        mixin("_ticks " ~ op ~ "= rhsConverted;");
        return this;
    }

    version (CoreUnittest) unittest
    {
        auto mt = MonoTimeImpl.currTime;
        const initial = mt;
        mt += Duration(0);
        assert(mt == initial);
        mt -= Duration(0);
        assert(mt == initial);

        // We reassign ticks in order to get the same rounding errors
        // that we should be getting with Duration (e.g. MonoTimeImpl may be
        // at a higher precision than hnsecs, meaning that 7333 would be
        // truncated when converting to hnsecs).
        long ticks = 7333;
        auto hnsecs = convClockFreq(ticks, ticksPerSecond, hnsecsPer!"seconds");
        ticks = convClockFreq(hnsecs, hnsecsPer!"seconds", ticksPerSecond);
        auto before = MonoTimeImpl(initial._ticks - ticks);

        assert((mt -= Duration(hnsecs)) == before);
        assert(mt  == before);
        assert((mt += Duration(hnsecs)) == initial);
        assert(mt  == initial);
    }


    /++
        The number of ticks in the monotonic time.

        Most programs should not use this directly, but it's exposed for those
        few programs that need it.

        The main reasons that a program might need to use ticks directly is if
        the system clock has higher precision than hnsecs, and the program needs
        that higher precision, or if the program needs to avoid the rounding
        errors caused by converting to hnsecs.
      +/
    @property long ticks() const pure nothrow @nogc
    {
        return _ticks;
    }

    version (CoreUnittest) unittest
    {
        const mt = MonoTimeImpl.currTime;
        assert(mt.ticks == mt._ticks);
    }


    /++
        The number of ticks that MonoTime has per second - i.e. the resolution
        or frequency of the system's monotonic clock.

        e.g. if the system clock had a resolution of microseconds, then
        ticksPerSecond would be $(D 1_000_000).
      +/
    static @property long ticksPerSecond() pure nothrow @nogc
    {
        return _ticksPerSecond[_clockIdx];
    }

    version (CoreUnittest) unittest
    {
        assert(MonoTimeImpl.ticksPerSecond == _ticksPerSecond[_clockIdx]);
    }


    ///
    string toString() const pure nothrow
    {
        static if (clockType == ClockType.normal)
            return "MonoTime(" ~ signedToTempString(_ticks) ~ " ticks, " ~ signedToTempString(ticksPerSecond) ~ " ticks per second)";
        else
            return "MonoTimeImpl!(ClockType." ~ _clockName ~ ")(" ~ signedToTempString(_ticks) ~ " ticks, " ~
                   signedToTempString(ticksPerSecond) ~ " ticks per second)";
    }

    version (CoreUnittest) unittest
    {
        import core.internal.util.math : min;

        static void eat(ref string s, const(char)[] exp)
        {
            assert(s[0 .. min($, exp.length)] == exp, s~" != "~exp);
            s = s[exp.length .. $];
        }

        immutable mt = MonoTimeImpl.currTime;
        auto str = mt.toString();
        static if (is(typeof(this) == MonoTime))
            eat(str, "MonoTime(");
        else
            eat(str, "MonoTimeImpl!(ClockType."~_clockName~")(");

        eat(str, signedToTempString(mt._ticks));
        eat(str, " ticks, ");
        eat(str, signedToTempString(ticksPerSecond));
        eat(str, " ticks per second)");
    }

private:

    // static immutable long _ticksPerSecond;

    version (CoreUnittest) unittest
    {
        assert(_ticksPerSecond[_clockIdx]);
    }


    package long _ticks;
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
    else version (Windows)
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
    else version (Darwin)
    {
        immutable long ticksPerSecond = machTicksPerSecond();
        foreach (i, typeStr; __traits(allMembers, ClockType))
        {
            // ensure we are only writing immutable data once
            if (tps[i] != 0)
                // should only be called once
                assert(0);
            tps[i] = ticksPerSecond;
        }
    }
    else version (Posix)
    {
        timespec ts;
        foreach (i, typeStr; __traits(allMembers, ClockType))
        {
            static if (typeStr != "second")
            {
                enum clockArg = _posixClock(__traits(getMember, ClockType, typeStr));
                if (clock_getres(clockArg, &ts) == 0)
                {
                    // ensure we are only writing immutable data once
                    if (tps[i] != 0)
                        // should only be called once
                        assert(0);

                    // For some reason, on some systems, clock_getres returns
                    // a resolution which is clearly wrong:
                    //  - it's a millisecond or worse, but the time is updated
                    //    much more frequently than that.
                    //  - it's negative
                    //  - it's zero
                    // In such cases, we'll just use nanosecond resolution.
                    tps[i] = ts.tv_sec != 0 || ts.tv_nsec <= 0 || ts.tv_nsec >= 1000
                        ? 1_000_000_000L : 1_000_000_000L / ts.tv_nsec;
                }
            }
        }
    }
    else version (DruntimeAbstractRt)
    {
        import external.core.time : initTicksPerSecond;

        initTicksPerSecond(tps);
    }
    else
        static assert(0, "Unsupported platform");
}

version (Darwin)
long machTicksPerSecond() @nogc nothrow
{
    // Be optimistic that ticksPerSecond (1e9*denom/numer) is integral. So far
    // so good on Darwin based platforms OS X, iOS.
    import core.internal.abort : abort;
    mach_timebase_info_data_t info;
    if (mach_timebase_info(&info) != 0)
        abort("Failed in mach_timebase_info().");

    long scaledDenom = 1_000_000_000L * info.denom;
    if (scaledDenom % info.numer != 0)
        abort("Non integral ticksPerSecond from mach_timebase_info.");
    return scaledDenom / info.numer;
}

version (CoreUnittest) deprecated
{
    package @property TickDuration currSystemTick() @trusted nothrow @nogc
    {
        import core.internal.abort : abort;
        version (Windows)
        {
            ulong ticks = void;
            QueryPerformanceCounter(cast(long*)&ticks);
            return TickDuration(ticks);
        }
        else version (Darwin)
        {
            static if (is(typeof(mach_absolute_time)))
                return TickDuration(cast(long)mach_absolute_time());
            else
            {
                timeval tv = void;
                gettimeofday(&tv, null);
                return TickDuration(tv.tv_sec * TickDuration.ticksPerSec +
                                    tv.tv_usec * TickDuration.ticksPerSec / 1000 / 1000);
            }
        }
        else version (Posix)
        {
            static if (is(typeof(clock_gettime)))
            {
                timespec ts = void;
                immutable error = clock_gettime(CLOCK_MONOTONIC, &ts);
                // CLOCK_MONOTONIC is supported and if tv_sec is long or larger
                // overflow won't happen before 292 billion years A.D.
                static if (ts.tv_sec.max < long.max)
                {
                    if (error)
                    {
                        import core.internal.abort : abort;
                        abort("Call to clock_gettime failed.");
                    }
                }
                return TickDuration(ts.tv_sec * TickDuration.ticksPerSec +
                                    ts.tv_nsec * TickDuration.ticksPerSec / 1000 / 1000 / 1000);
            }
            else
            {
                timeval tv = void;
                gettimeofday(&tv, null);
                return TickDuration(tv.tv_sec * TickDuration.ticksPerSec +
                                    tv.tv_usec * TickDuration.ticksPerSec / 1000 / 1000);
            }
        }
    }
}
