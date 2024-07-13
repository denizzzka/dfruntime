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

version (Windows)
{
import core.sys.windows.winbase /+: QueryPerformanceCounter, QueryPerformanceFrequency+/;
}
else version (Posix)
{
import core.sys.posix.time;
import core.sys.posix.sys.time;
}

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

//This probably should be moved somewhere else in druntime which
//is Darwin-specific.
version (Darwin)
{

public import core.sys.darwin.mach.kern_return;

extern(C) nothrow @nogc
{

struct mach_timebase_info_data_t
{
    uint numer;
    uint denom;
}

alias mach_timebase_info_data_t* mach_timebase_info_t;

kern_return_t mach_timebase_info(mach_timebase_info_t);

ulong mach_absolute_time();

}

}

/++
    What type of clock to use with $(LREF MonoTime) / $(LREF MonoTimeImpl) or
    $(D std.datetime.Clock.currTime). They default to $(D ClockType.normal),
    and most programs do not need to ever deal with the others.

    The other $(D ClockType)s are provided so that other clocks provided by the
    underlying C, system calls can be used with $(LREF MonoTimeImpl) or
    $(D std.datetime.Clock.currTime) without having to use the C API directly.

    In the case of the monotonic time, $(LREF MonoTimeImpl) is templatized on
    $(D ClockType), whereas with $(D std.datetime.Clock.currTime), its a runtime
    argument, since in the case of the monotonic time, the type of the clock
    affects the resolution of a $(LREF MonoTimeImpl) object, whereas with
    $(REF SysTime, std,datetime), its resolution is always hecto-nanoseconds
    regardless of the source of the time.

    $(D ClockType.normal), $(D ClockType.coarse), and $(D ClockType.precise)
    work with both $(D Clock.currTime) and $(LREF MonoTimeImpl).
    $(D ClockType.second) only works with $(D Clock.currTime). The others only
    work with $(LREF MonoTimeImpl).
  +/
version (CoreDdoc) enum ClockType
{
    /++
        Use the normal clock.
      +/
    normal = 0,

    /++
        $(BLUE Linux,OpenBSD-Only)

        Uses $(D CLOCK_BOOTTIME).
      +/
    bootTime = 1,

    /++
        Use the coarse clock, not the normal one (e.g. on Linux, that would be
        $(D CLOCK_REALTIME_COARSE) instead of $(D CLOCK_REALTIME) for
        $(D clock_gettime) if a function is using the realtime clock). It's
        generally faster to get the time with the coarse clock than the normal
        clock, but it's less precise (e.g. 1 msec instead of 1 usec or 1 nsec).
        Howeover, it $(I is) guaranteed to still have sub-second precision
        (just not as high as with $(D ClockType.normal)).

        On systems which do not support a coarser clock,
        $(D MonoTimeImpl!(ClockType.coarse)) will internally use the same clock
        as $(D MonoTime) does, and $(D Clock.currTime!(ClockType.coarse)) will
        use the same clock as $(D Clock.currTime). This is because the coarse
        clock is doing the same thing as the normal clock (just at lower
        precision), whereas some of the other clock types
        (e.g. $(D ClockType.processCPUTime)) mean something fundamentally
        different. So, treating those as $(D ClockType.normal) on systems where
        they weren't natively supported would give misleading results.

        Most programs should not use the coarse clock, exactly because it's
        less precise, and most programs don't need to get the time often
        enough to care, but for those rare programs that need to get the time
        extremely frequently (e.g. hundreds of thousands of times a second) but
        don't care about high precision, the coarse clock might be appropriate.

        Currently, only Linux and FreeBSD/DragonFlyBSD support a coarser clock, and on other
        platforms, it's treated as $(D ClockType.normal).
      +/
    coarse = 2,

    /++
        Uses a more precise clock than the normal one (which is already very
        precise), but it takes longer to get the time. Similarly to
        $(D ClockType.coarse), if it's used on a system that does not support a
        more precise clock than the normal one, it's treated as equivalent to
        $(D ClockType.normal).

        Currently, only FreeBSD/DragonFlyBSD supports a more precise clock, where it uses
        $(D CLOCK_MONOTONIC_PRECISE) for the monotonic time and
        $(D CLOCK_REALTIME_PRECISE) for the wall clock time.
      +/
    precise = 3,

    /++
        $(BLUE Linux,OpenBSD,Solaris-Only)

        Uses $(D CLOCK_PROCESS_CPUTIME_ID).
      +/
    processCPUTime = 4,

    /++
        $(BLUE Linux-Only)

        Uses $(D CLOCK_MONOTONIC_RAW).
      +/
    raw = 5,

    /++
        Uses a clock that has a precision of one second (contrast to the coarse
        clock, which has sub-second precision like the normal clock does).

        FreeBSD/DragonFlyBSD are the only systems which specifically have a clock set up for
        this (it has $(D CLOCK_SECOND) to use with $(D clock_gettime) which
        takes advantage of an in-kernel cached value), but on other systems, the
        fastest function available will be used, and the resulting $(D SysTime)
        will be rounded down to the second if the clock that was used gave the
        time at a more precise resolution. So, it's guaranteed that the time
        will be given at a precision of one second and it's likely the case that
        will be faster than $(D ClockType.normal), since there tend to be
        several options on a system to get the time at low resolutions, and they
        tend to be faster than getting the time at high resolutions.

        So, the primary difference between $(D ClockType.coarse) and
        $(D ClockType.second) is that $(D ClockType.coarse) sacrifices some
        precision in order to get speed but is still fairly precise, whereas
        $(D ClockType.second) tries to be as fast as possible at the expense of
        all sub-second precision.
      +/
    second = 6,

    /++
        $(BLUE Linux,OpenBSD,Solaris-Only)

        Uses $(D CLOCK_THREAD_CPUTIME_ID).
      +/
    threadCPUTime = 7,

    /++
        $(BLUE DragonFlyBSD,FreeBSD,OpenBSD-Only)

        Uses $(D CLOCK_UPTIME).
      +/
    uptime = 8,

    /++
        $(BLUE FreeBSD-Only)

        Uses $(D CLOCK_UPTIME_FAST).
      +/
    uptimeCoarse = 9,

    /++
        $(BLUE FreeBSD-Only)

        Uses $(D CLOCK_UPTIME_PRECISE).
      +/
    uptimePrecise = 10,
}
else version (Windows) enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    second = 6,
}
else version (Darwin) enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    second = 6,
}
else version (linux) enum ClockType
{
    normal = 0,
    bootTime = 1,
    coarse = 2,
    precise = 3,
    processCPUTime = 4,
    raw = 5,
    second = 6,
    threadCPUTime = 7,
}
else version (FreeBSD) enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    second = 6,
    uptime = 8,
    uptimeCoarse = 9,
    uptimePrecise = 10,
}
else version (NetBSD) enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    second = 6,
}
else version (OpenBSD) enum ClockType
{
    normal = 0,
    bootTime = 1,
    coarse = 2,
    precise = 3,
    processCPUTime = 4,
    second = 6,
    threadCPUTime = 7,
    uptime = 8,
}
else version (DragonFlyBSD) enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    second = 6,
    uptime = 8,
    uptimeCoarse = 9,
    uptimePrecise = 10,
}
else version (Solaris) enum ClockType
{
    normal = 0,
    coarse = 2,
    precise = 3,
    processCPUTime = 4,
    second = 6,
    threadCPUTime = 7,
}
else
{
    // It needs to be decided (and implemented in an appropriate version branch
    // here) which clock types new platforms are going to support. At minimum,
    // the ones _not_ marked with $(D Blue Foo-Only) should be supported.
    //TODO: move ClockType definition from core.std.*
    public import core.stdc.time_impl: ClockType;
}

// private, used to translate clock type to proper argument to clock_xxx
// functions on posix systems
version (CoreDdoc)
    private int _posixClock(ClockType clockType) { return 0; }
else
version (Posix)
{
    private auto _posixClock(ClockType clockType)
    {
        version (linux)
        {
            import core.sys.linux.time;
            with(ClockType) final switch (clockType)
            {
            case bootTime: return CLOCK_BOOTTIME;
            case coarse: return CLOCK_MONOTONIC_COARSE;
            case normal: return CLOCK_MONOTONIC;
            case precise: return CLOCK_MONOTONIC;
            case processCPUTime: return CLOCK_PROCESS_CPUTIME_ID;
            case raw: return CLOCK_MONOTONIC_RAW;
            case threadCPUTime: return CLOCK_THREAD_CPUTIME_ID;
            case second: assert(0);
            }
        }
        else version (FreeBSD)
        {
            import core.sys.freebsd.time;
            with(ClockType) final switch (clockType)
            {
            case coarse: return CLOCK_MONOTONIC_FAST;
            case normal: return CLOCK_MONOTONIC;
            case precise: return CLOCK_MONOTONIC_PRECISE;
            case uptime: return CLOCK_UPTIME;
            case uptimeCoarse: return CLOCK_UPTIME_FAST;
            case uptimePrecise: return CLOCK_UPTIME_PRECISE;
            case second: assert(0);
            }
        }
        else version (NetBSD)
        {
            import core.sys.netbsd.time;
            with(ClockType) final switch (clockType)
            {
            case coarse: return CLOCK_MONOTONIC;
            case normal: return CLOCK_MONOTONIC;
            case precise: return CLOCK_MONOTONIC;
            case second: assert(0);
            }
        }
        else version (OpenBSD)
        {
            import core.sys.openbsd.time;
            with(ClockType) final switch (clockType)
            {
            case bootTime: return CLOCK_BOOTTIME;
            case coarse: return CLOCK_MONOTONIC;
            case normal: return CLOCK_MONOTONIC;
            case precise: return CLOCK_MONOTONIC;
            case processCPUTime: return CLOCK_PROCESS_CPUTIME_ID;
            case threadCPUTime: return CLOCK_THREAD_CPUTIME_ID;
            case uptime: return CLOCK_UPTIME;
            case second: assert(0);
            }
        }
        else version (DragonFlyBSD)
        {
            import core.sys.dragonflybsd.time;
            with(ClockType) final switch (clockType)
            {
            case coarse: return CLOCK_MONOTONIC_FAST;
            case normal: return CLOCK_MONOTONIC;
            case precise: return CLOCK_MONOTONIC_PRECISE;
            case uptime: return CLOCK_UPTIME;
            case uptimeCoarse: return CLOCK_UPTIME_FAST;
            case uptimePrecise: return CLOCK_UPTIME_PRECISE;
            case second: assert(0);
            }
        }
        else version (Solaris)
        {
            import core.sys.solaris.time;
            with(ClockType) final switch (clockType)
            {
            case coarse: return CLOCK_MONOTONIC;
            case normal: return CLOCK_MONOTONIC;
            case precise: return CLOCK_MONOTONIC;
            case processCPUTime: return CLOCK_PROCESS_CPUTIME_ID;
            case threadCPUTime: return CLOCK_THREAD_CPUTIME_ID;
            case second: assert(0);
            }
        }
        else
            // It needs to be decided (and implemented in an appropriate
            // version branch here) which clock types new platforms are going
            // to support. Also, ClockType's documentation should be updated to
            // mention it if a new platform uses anything that's not supported
            // on all platforms..
            assert(0, "What are the monotonic clock types supported by this system?");
    }
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

    version (Windows)
    {
        static if (clockType != ClockType.coarse &&
                  clockType != ClockType.normal &&
                  clockType != ClockType.precise)
        {
            static assert(0, "ClockType." ~ _clockName ~
                             " is not supported by MonoTimeImpl on this system.");
        }
    }
    else version (Darwin)
    {
        static if (clockType != ClockType.coarse &&
                  clockType != ClockType.normal &&
                  clockType != ClockType.precise)
        {
            static assert(0, "ClockType." ~ _clockName ~
                             " is not supported by MonoTimeImpl on this system.");
        }
    }
    else version (Posix)
    {
        enum clockArg = _posixClock(clockType);
    }
    else version (DruntimeAbstractRt)
    {
    }
    else
        static assert(0, "Unsupported platform");

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
