/**
 * D header file for C99 <stdio.h>
 *
 * $(C_HEADER_DESCRIPTION pubs.opengroup.org/onlinepubs/009695399/basedefs/_stdio.h.html, _stdio.h)
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly,
 *            Alex Rønne Petersen
 * Source:    https://github.com/dlang/dmd/blob/master/druntime/src/core/stdc/stdio.d
 * Standards: ISO/IEC 9899:1999 (E)
 */

module core.stdc.stdio;

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

private
{
    import core.stdc.config;
    import core.stdc.stdarg; // for va_list
    import core.stdc.stdint : intptr_t;

  version (FreeBSD)
  {
    import core.sys.posix.sys.types;
  }
  else version (OpenBSD)
  {
    import core.sys.posix.sys.types;
  }
  version (NetBSD)
  {
    import core.sys.posix.sys.types;
  }
  version (DragonFlyBSD)
  {
    import core.sys.posix.sys.types;
  }
}

extern (C):
nothrow:
@nogc:

// BUFSIZ, EOF, etc
public import core.stdc.stdio_details;

enum
{
    /// Offset is relative to the beginning
    SEEK_SET,
    /// Offset is relative to the current position
    SEEK_CUR,
    /// Offset is relative to the end
    SEEK_END
}

// fpos_t, FILE, etc
public import core.stdc.stdio_details;

enum
{
    ///
    _F_RDWR = 0x0003, // non-standard
    ///
    _F_READ = 0x0001, // non-standard
    ///
    _F_WRIT = 0x0002, // non-standard
    ///
    _F_BUF  = 0x0004, // non-standard
    ///
    _F_LBUF = 0x0008, // non-standard
    ///
    _F_ERR  = 0x0010, // non-standard
    ///
    _F_EOF  = 0x0020, // non-standard
    ///
    _F_BIN  = 0x0040, // non-standard
    ///
    _F_IN   = 0x0080, // non-standard
    ///
    _F_OUT  = 0x0100, // non-standard
    ///
    _F_TERM = 0x0200, // non-standard
}

public import core.stdc.stdio_details: stdin, stdout, stderr;

///
int remove(scope const char* filename);
///
int rename(scope const char* from, scope const char* to);

///
@trusted FILE* tmpfile(); // No unsafe pointer manipulation.
///
char* tmpnam(char* s);

///
int   fclose(FILE* stream);

// No unsafe pointer manipulation.
@trusted
{
    ///
    int   fflush(FILE* stream);
}

///
FILE* fopen(scope const char* filename, scope const char* mode);
///
FILE* freopen(scope const char* filename, scope const char* mode, FILE* stream);

///
void setbuf(FILE* stream, char* buf);
///
int  setvbuf(FILE* stream, char* buf, int mode, size_t size);

version (MinGW)
{
    // Prefer the MinGW versions over the MSVC ones, as the latter don't handle
    // reals at all.
    ///
    pragma(printf)
    int __mingw_fprintf(FILE* stream, scope const char* format, scope const ...);
    ///
    alias __mingw_fprintf fprintf;

    ///
    pragma(scanf)
    int __mingw_fscanf(FILE* stream, scope const char* format, scope ...);
    ///
    alias __mingw_fscanf fscanf;

    ///
    pragma(printf)
    int __mingw_sprintf(scope char* s, scope const char* format, scope const ...);
    ///
    alias __mingw_sprintf sprintf;

    ///
    pragma(scanf)
    int __mingw_sscanf(scope const char* s, scope const char* format, scope ...);
    ///
    alias __mingw_sscanf sscanf;

    ///
    pragma(printf)
    int __mingw_vfprintf(FILE* stream, scope const char* format, va_list arg);
    ///
    alias __mingw_vfprintf vfprintf;

    ///
    pragma(scanf)
    int __mingw_vfscanf(FILE* stream, scope const char* format, va_list arg);
    ///
    alias __mingw_vfscanf vfscanf;

    ///
    pragma(printf)
    int __mingw_vsprintf(scope char* s, scope const char* format, va_list arg);
    ///
    alias __mingw_vsprintf vsprintf;

    ///
    pragma(scanf)
    int __mingw_vsscanf(scope const char* s, scope const char* format, va_list arg);
    ///
    alias __mingw_vsscanf vsscanf;

    ///
    pragma(printf)
    int __mingw_vprintf(scope const char* format, va_list arg);
    ///
    alias __mingw_vprintf vprintf;

    ///
    pragma(scanf)
    int __mingw_vscanf(scope const char* format, va_list arg);
    ///
    alias __mingw_vscanf vscanf;

    ///
    pragma(printf)
    int __mingw_printf(scope const char* format, scope const ...);
    ///
    alias __mingw_printf printf;

    ///
    pragma(scanf)
    int __mingw_scanf(scope const char* format, scope ...);
    ///
    alias __mingw_scanf scanf;
}
else version (CRuntime_Glibc)
{
    ///
    pragma(printf)
    int fprintf(FILE* stream, scope const char* format, scope const ...);
    ///
    pragma(scanf)
    int __isoc99_fscanf(FILE* stream, scope const char* format, scope ...);
    ///
    alias fscanf = __isoc99_fscanf;
    ///
    pragma(printf)
    int sprintf(scope char* s, scope const char* format, scope const ...);
    ///
    pragma(scanf)
    int __isoc99_sscanf(scope const char* s, scope const char* format, scope ...);
    ///
    alias sscanf = __isoc99_sscanf;
    ///
    pragma(printf)
    int vfprintf(FILE* stream, scope const char* format, va_list arg);
    ///
    pragma(scanf)
    int __isoc99_vfscanf(FILE* stream, scope const char* format, va_list arg);
    ///
    alias vfscanf = __isoc99_vfscanf;
    ///
    pragma(printf)
    int vsprintf(scope char* s, scope const char* format, va_list arg);
    ///
    pragma(scanf)
    int __isoc99_vsscanf(scope const char* s, scope const char* format, va_list arg);
    ///
    alias vsscanf = __isoc99_vsscanf;
    ///
    pragma(printf)
    int vprintf(scope const char* format, va_list arg);
    ///
    pragma(scanf)
    int __isoc99_vscanf(scope const char* format, va_list arg);
    ///
    alias vscanf = __isoc99_vscanf;
    ///
    pragma(printf)
    int printf(scope const char* format, scope const ...);
    ///
    pragma(scanf)
    int __isoc99_scanf(scope const char* format, scope ...);
    ///
    alias scanf = __isoc99_scanf;
}
else
{
    ///
    pragma(printf)
    int fprintf(FILE* stream, scope const char* format, scope const ...);
    ///
    pragma(scanf)
    int fscanf(FILE* stream, scope const char* format, scope ...);
    ///
    pragma(printf)
    int sprintf(scope char* s, scope const char* format, scope const ...);
    ///
    pragma(scanf)
    int sscanf(scope const char* s, scope const char* format, scope ...);
    ///
    pragma(printf)
    int vfprintf(FILE* stream, scope const char* format, va_list arg);
    ///
    pragma(scanf)
    int vfscanf(FILE* stream, scope const char* format, va_list arg);
    ///
    pragma(printf)
    int vsprintf(scope char* s, scope const char* format, va_list arg);
    ///
    pragma(scanf)
    int vsscanf(scope const char* s, scope const char* format, va_list arg);
    ///
    pragma(printf)
    int vprintf(scope const char* format, va_list arg);
    ///
    pragma(scanf)
    int vscanf(scope const char* format, va_list arg);
    ///
    pragma(printf)
    int printf(scope const char* format, scope const ...);
    ///
    pragma(scanf)
    int scanf(scope const char* format, scope ...);
}

// No unsafe pointer manipulation.
@trusted
{
    ///
    int fgetc(FILE* stream);
    ///
    int fputc(int c, FILE* stream);
}

///
char* fgets(char* s, int n, FILE* stream);
///
int   fputs(scope const char* s, FILE* stream);
///
char* gets(char* s);
///
int   puts(scope const char* s);

// No unsafe pointer manipulation.
extern (D) @trusted
{
    ///
    int getchar()()                 { return getc(stdin);     }
    ///
    int putchar()(int c)            { return putc(c,stdout);  }
}

///
alias getc = fgetc;
///
alias putc = fputc;

///
@trusted int ungetc(int c, FILE* stream); // No unsafe pointer manipulation.

///
size_t fread(scope void* ptr, size_t size, size_t nmemb, FILE* stream);
///
size_t fwrite(scope const void* ptr, size_t size, size_t nmemb, FILE* stream);

// No unsafe pointer manipulation.
@trusted
{
    ///
    int fgetpos(FILE* stream, scope fpos_t * pos);
    ///
    int fsetpos(FILE* stream, scope const fpos_t* pos);

    ///
    int    fseek(FILE* stream, c_long offset, int whence);
    ///
    c_long ftell(FILE* stream);
}

// snprintf, etc
public import core.stdc.stdio_details;

///
void perror(scope const char* s);

version (CRuntime_DigitalMars)
{
    version (none)
        import core.sys.windows.windows : HANDLE, _WaitSemaphore, _ReleaseSemaphore;
    else
    {
        // too slow to import windows
        private alias void* HANDLE;
        private void _WaitSemaphore(int iSemaphore);
        private void _ReleaseSemaphore(int iSemaphore);
    }

    enum
    {
        ///
        FHND_APPEND     = 0x04,
        ///
        FHND_DEVICE     = 0x08,
        ///
        FHND_TEXT       = 0x10,
        ///
        FHND_BYTE       = 0x20,
        ///
        FHND_WCHAR      = 0x40,
    }

    private enum _MAX_SEMAPHORES = 10 + _NFILE;
    private enum _semIO = 3;

    private extern __gshared short[_MAX_SEMAPHORES] _iSemLockCtrs;
    private extern __gshared int[_MAX_SEMAPHORES] _iSemThreadIds;
    private extern __gshared int[_MAX_SEMAPHORES] _iSemNestCount;
    private extern __gshared HANDLE[_NFILE] _osfhnd;
    extern shared ubyte[_NFILE] __fhnd_info;

    // this is copied from semlock.h in DMC's runtime.
    private void LockSemaphore()(uint num)
    {
        asm nothrow @nogc
        {
            mov EDX, num;
            lock;
            inc _iSemLockCtrs[EDX * 2];
            jz lsDone;
            push EDX;
            call _WaitSemaphore;
            add ESP, 4;
        }

    lsDone: {}
    }

    // this is copied from semlock.h in DMC's runtime.
    private void UnlockSemaphore()(uint num)
    {
        asm nothrow @nogc
        {
            mov EDX, num;
            lock;
            dec _iSemLockCtrs[EDX * 2];
            js usDone;
            push EDX;
            call _ReleaseSemaphore;
            add ESP, 4;
        }

    usDone: {}
    }

    // This converts a HANDLE to a file descriptor in DMC's runtime
    ///
    int _handleToFD()(HANDLE h, int flags)
    {
        LockSemaphore(_semIO);
        scope(exit) UnlockSemaphore(_semIO);

        foreach (fd; 0 .. _NFILE)
        {
            if (!_osfhnd[fd])
            {
                _osfhnd[fd] = h;
                __fhnd_info[fd] = cast(ubyte)flags;
                return fd;
            }
        }

        return -1;
    }

    ///
    HANDLE _fdToHandle()(int fd)
    {
        // no semaphore is required, once inserted, a file descriptor
        // doesn't change.
        if (fd < 0 || fd >= _NFILE)
            return null;

        return _osfhnd[fd];
    }

    enum
    {
        ///
        STDIN_FILENO  = 0,
        ///
        STDOUT_FILENO = 1,
        ///
        STDERR_FILENO = 2,
    }

    int open(scope const(char)* filename, int flags, ...); ///
    alias _open = open; ///
    int _wopen(scope const wchar* filename, int oflag, ...); ///
    int sopen(scope const char* filename, int oflag, int shflag, ...); ///
    alias _sopen = sopen; ///
    int _wsopen(scope const wchar* filename, int oflag, int shflag, ...); ///
    int close(int fd); ///
    alias _close = close; ///
    FILE *fdopen(int fd, scope const(char)* flags); ///
    alias _fdopen = fdopen; ///
    FILE *_wfdopen(int fd, scope const(wchar)* flags); ///

}
else version (CRuntime_Microsoft)
{
    int _open(scope const char* filename, int oflag, ...); ///
    int _wopen(scope const wchar* filename, int oflag, ...); ///
    int _sopen(scope const char* filename, int oflag, int shflag, ...); ///
    int _wsopen(scope const wchar* filename, int oflag, int shflag, ...); ///
    int _close(int fd); ///
    FILE *_fdopen(int fd, scope const(char)* flags); ///
    FILE *_wfdopen(int fd, scope const(wchar)* flags); ///
}

version (Windows)
{
    // file open flags
    enum
    {
        _O_RDONLY = 0x0000, ///
        O_RDONLY = _O_RDONLY, ///
        _O_WRONLY = 0x0001, ///
        O_WRONLY = _O_WRONLY, ///
        _O_RDWR   = 0x0002, ///
        O_RDWR = _O_RDWR, ///
        _O_APPEND = 0x0008, ///
        O_APPEND = _O_APPEND, ///
        _O_CREAT  = 0x0100, ///
        O_CREAT = _O_CREAT, ///
        _O_TRUNC  = 0x0200, ///
        O_TRUNC = _O_TRUNC, ///
        _O_EXCL   = 0x0400, ///
        O_EXCL = _O_EXCL, ///
        _O_TEXT   = 0x4000, ///
        O_TEXT = _O_TEXT, ///
        _O_BINARY = 0x8000, ///
        O_BINARY = _O_BINARY, ///
        _O_WTEXT = 0x10000, ///
        _O_U16TEXT = 0x20000, ///
        _O_U8TEXT = 0x40000, ///
        _O_ACCMODE = (_O_RDONLY|_O_WRONLY|_O_RDWR), ///
        O_ACCMODE = _O_ACCMODE, ///
        _O_RAW = _O_BINARY, ///
        O_RAW = _O_BINARY, ///
        _O_NOINHERIT = 0x0080, ///
        O_NOINHERIT = _O_NOINHERIT, ///
        _O_TEMPORARY = 0x0040, ///
        O_TEMPORARY = _O_TEMPORARY, ///
        _O_SHORT_LIVED = 0x1000, ///
        _O_SEQUENTIAL = 0x0020, ///
        O_SEQUENTIAL = _O_SEQUENTIAL, ///
        _O_RANDOM = 0x0010, ///
        O_RANDOM = _O_RANDOM, ///
    }

    enum
    {
        _S_IREAD  = 0x0100, /// read permission, owner
        S_IREAD = _S_IREAD, /// read permission, owner
        _S_IWRITE = 0x0080, /// write permission, owner
        S_IWRITE = _S_IWRITE, /// write permission, owner
    }

    enum
    {
        _SH_DENYRW = 0x10, /// deny read/write mode
        SH_DENYRW = _SH_DENYRW, /// deny read/write mode
        _SH_DENYWR = 0x20, /// deny write mode
        SH_DENYWR = _SH_DENYWR, /// deny write mode
        _SH_DENYRD = 0x30, /// deny read mode
        SH_DENYRD = _SH_DENYRD, /// deny read mode
        _SH_DENYNO = 0x40, /// deny none mode
        SH_DENYNO = _SH_DENYNO, /// deny none mode
    }
}
