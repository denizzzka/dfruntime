/**
 * Implementation of code coverage analyzer.
 *
 * Copyright: Copyright Digital Mars 1995 - 2015.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Walter Bright, Sean Kelly
 * Source: $(DRUNTIMESRC rt/_cover.d)
 */

module rt.cover_impl;

package:

import core.sys.windows.basetsd: HANDLE;
import core.sys.windows.winbase: LOCKFILE_EXCLUSIVE_LOCK, LockFileEx, OVERLAPPED, SetEndOfFile;

import core.stdc.stdio;
import core.internal.utf: toUTF16z;

void setFileLen(T)(ref T flst)
{
    SetEndOfFile(handle(fileno(flst)));
}

immutable char sep = '\\';

string getExt( string name )
{
    auto i = name.length;

    while ( i > 0 )
    {
        if ( name[i - 1] == '.' )
            return name[i .. $];
        --i;

        if ( name[i] == ':' || name[i] == '\\' )
            break;
    }
    return null;
}

auto openFile(string name)
{
    return _wfopen(toUTF16z(name), "rb"w.ptr);
}

// open/create file for read/write, pointer at beginning
FILE* openOrCreateFile(string name)
{
    import core.internal.utf : toUTF16z;

    immutable fd = _wopen(toUTF16z(name), _O_RDWR | _O_CREAT | _O_BINARY, _S_IREAD | _S_IWRITE);

    return _fdopen(fd, "r+b");
}

HANDLE handle(int fd)
{
    version (CRuntime_DigitalMars)
        return _fdToHandle(fd);
    else
        return cast(HANDLE)_get_osfhandle(fd);
}

void lockFile(FILE* flst)
{
    auto fd = fileno(flst);
    OVERLAPPED off;
    // exclusively lock first byte
    LockFileEx(handle(fd), LOCKFILE_EXCLUSIVE_LOCK, 0, 1, 0, &off);
}

version (Windows) extern (C) nothrow @nogc FILE* _wfopen(scope const wchar* filename, scope const wchar* mode);
