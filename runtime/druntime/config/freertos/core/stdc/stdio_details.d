module core.stdc.stdio_details;

import core.stdc.config: c_long;

nothrow:
@nogc:
extern(C):

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

//FIXME: Newlib is supported in official druntime, create tag for picolibc?
version (CRuntime_Newlib)
{
    __gshared FILE* stdin;
    __gshared FILE* stdout;
    __gshared FILE* stderr;
}
else // picolibc
{
    extern __gshared FILE* stdin;
    extern __gshared FILE* stdout;
    extern __gshared FILE* stderr;
}

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

extern(C):

import core.stdc.stdarg: va_list;

///
pragma(printf)
int snprintf(scope char* s, size_t n, scope const char* format, ...);

///
pragma(printf)
int vsnprintf(scope char* s, size_t n, scope const char* format, va_list arg);

void flockfile(FILE *filehandle);
void funlockfile(FILE *filehandle);

@safe:

FILE* fdopen(int, const scope char*);
pure int feof(FILE* stream);
pure int ferror(FILE* stream);
pure void clearerr(FILE*);
int fsync(int);
int fseeko(FILE*, off_t, int);

import internal.binding: __off_t;
alias off_t = __off_t;

off_t ftello(FILE*);
void rewind(FILE* stream);
int fileno(FILE *);
