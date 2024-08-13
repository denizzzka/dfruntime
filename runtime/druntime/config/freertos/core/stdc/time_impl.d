///
module core.stdc.time_impl;

//~ import core.stdc.config: c_long; //FIXME: https://issues.dlang.org/show_bug.cgi?id=24666
version (D_LP64) {} else
alias c_long = int;

alias time_t = c_long;

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

// from picolibc
struct timeval {
    long    tv_sec;     /* seconds */
    long    tv_usec;    /* and microseconds */
}

version (ESP_IDF)
{
    // newlibc
}
else
extern(C) int gettimeofday(timeval* tv, void*) // timezone_t* is normally void*
{
    tv.tv_sec = 123;
    tv.tv_usec = 456;

    assert(false, "not implemented");
}

extern(C) void tzset();
