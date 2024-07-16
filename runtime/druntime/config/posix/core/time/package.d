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

version (all)
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

    static assert(0, "Unsupported platform");
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

version (all) deprecated
{
    package @property TickDuration currSystemTick() @trusted nothrow @nogc
    {
        import core.internal.abort : abort;
        version (Darwin)
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
        else
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

package
{
    deprecated auto getTicksPerSec()
    {
        long ticksPerSec;

        version (Darwin)
        {
            ticksPerSec = machTicksPerSecond();
        }
        else version (Posix)
        {
            static if (is(typeof(clock_gettime)))
            {
                timespec ts;

                if (clock_getres(CLOCK_MONOTONIC, &ts) != 0)
                    ticksPerSec = 0;
                else
                {
                    //For some reason, on some systems, clock_getres returns
                    //a resolution which is clearly wrong (it's a millisecond
                    //or worse, but the time is updated much more frequently
                    //than that). In such cases, we'll just use nanosecond
                    //resolution.
                    ticksPerSec = ts.tv_nsec >= 1000 ? 1_000_000_000
                                                     : 1_000_000_000 / ts.tv_nsec;
                }
            }
            else
                ticksPerSec = 1_000_000;
        }
        else
            static assert(0, "Unsupported platform");

        return ticksPerSec;
    }
}

package long getCurrMonoTime(MT, alias ClockType clockType)() @trusted nothrow @nogc
{

    version (Darwin)
        return mach_absolute_time();
    else version (Posix)
    {
        enum clockArg = _posixClock(clockType);
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

        return convClockFreq(ts.tv_sec * 1_000_000_000L + ts.tv_nsec,
                                          1_000_000_000L,
                                          MT.ticksPerSecond);
    }
}
