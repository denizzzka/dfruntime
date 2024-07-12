module core.stdc.stdio_details;

import core.stdc.config: c_long;

nothrow:
@nogc:

///
alias fpos_t = c_long;

///
alias _iobuf = FILE;

enum
{
    ///
    _IOFBF = 0,
    ///
    _IOLBF = 1,
    ///
    _IONBF = 2,
}

///
struct FILE;

__gshared FILE* stdin;
__gshared FILE* stdout;
__gshared FILE* stderr;

enum
{
    ///
    BUFSIZ       = 4096,
    ///
    EOF          = -1,
    ///
    FOPEN_MAX    = 16,
    ///
    FILENAME_MAX = 4095,
    ///
    TMP_MAX      = 238328,
    ///
    L_tmpnam     = 20
}

///
pragma(printf)
extern(C) int snprintf(scope char* s, size_t n, scope const char* format, ...);

//~ ///
//~ pragma(printf)
//~ extern(C) int sprintf(scope char* s, scope const char* format, scope const ...);