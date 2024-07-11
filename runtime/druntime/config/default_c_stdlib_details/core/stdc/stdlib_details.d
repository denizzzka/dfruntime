module core.stdc.stdlib_details;

nothrow:
@nogc:

///
version (Windows)      enum RAND_MAX = 0x7fff;
else version (CRuntime_Glibc)  enum RAND_MAX = 0x7fffffff;
else version (Darwin)  enum RAND_MAX = 0x7fffffff;
else version (FreeBSD) enum RAND_MAX = 0x7ffffffd;
else version (NetBSD)  enum RAND_MAX = 0x7fffffff;
else version (OpenBSD) enum RAND_MAX = 0x7fffffff;
else version (DragonFlyBSD) enum RAND_MAX = 0x7fffffff;
else version (Solaris) enum RAND_MAX = 0x7fff;
else version (CRuntime_Bionic) enum RAND_MAX = 0x7fffffff;
else version (CRuntime_Musl) enum RAND_MAX = 0x7fffffff;
else version (CRuntime_Newlib) enum RAND_MAX = 0x7fffffff;
else version (CRuntime_UClibc) enum RAND_MAX = 0x7fffffff;
else version (CRuntime_Abstract) public import external.libc.stdlib: RAND_MAX;
else version (WASI) enum RAND_MAX = 0x7fffffff;
else static assert( false, "Unsupported platform" );

///
version (DigitalMars)
{
    // See malloc comment about @trusted.
    void* alloca(size_t size) pure; // non-standard
}
else version (GNU)
{
    void* alloca(size_t size) pure; // compiler intrinsic
}
else version (LDC)
{
    pragma(LDC_alloca)
    void* alloca(size_t size) pure;
}

version (CRuntime_Microsoft)
{
    ///
    ulong  _strtoui64(scope inout(char)*, scope inout(char)**,int);
    ///
    ulong  _wcstoui64(scope inout(wchar)*, scope inout(wchar)**,int);

    ///
    long  _strtoi64(scope inout(char)*, scope inout(char)**,int);
    ///
    long  _wcstoi64(scope inout(wchar)*, scope inout(wchar)**,int);
}
