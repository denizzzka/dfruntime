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

import core.sys.posix.fcntl;
import core.sys.posix.unistd;
import core.stdc.stdio;

void setFileLen(T)(ref T flst)
{
    ftruncate(fileno(flst), ftell(flst));
}

const char sep = '/';

string getExt( string name )
{
    auto i = name.length;

    while ( i > 0 )
    {
        if ( name[i - 1] == '.' )
            return name[i .. $];
        --i;

        if ( name[i] == '/' )
            break;
    }
    return null;
}

auto openFile(string name)
{
    return fopen((name ~ '\0').ptr, "rb".ptr);
}

// open/create file for read/write, pointer at beginning
FILE* openOrCreateFile(string name)
{
    import core.internal.utf : toUTF16z;

    immutable fd = open((name ~ '\0').ptr, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP |
                S_IROTH | S_IWOTH);

    import core.sys.posix.stdio;

    return fdopen(fd, "r+b");
}

void lockFile(int fd)
{
    version (CRuntime_Bionic)
    {
        import core.sys.bionic.fcntl : LOCK_EX;
        import core.sys.bionic.unistd : flock;
        flock(fd, LOCK_EX); // exclusive lock
    }
    else
        lockf(fd, F_LOCK, 0); // exclusive lock
}

void splitLines( char[] buf, ref char[][] lines )
{
    size_t  beg = 0,
            pos = 0;

    lines.length = 0;
    for ( ; pos < buf.length; ++pos )
    {
        char c = buf[pos];

        switch ( buf[pos] )
        {
        case '\r':
        case '\n':
            lines ~= buf[beg .. pos];
            beg = pos + 1;
            if ( buf[pos] == '\r' && pos < buf.length - 1 && buf[pos + 1] == '\n' )
            {
                ++pos; ++beg;
            }
            continue;
        default:
            continue;
        }
    }
    if ( beg != pos )
    {
        lines ~= buf[beg .. pos];
    }
}


char[] expandTabs( char[] str, int tabsize = 8 )
{
    const dchar LS = '\u2028'; // UTF line separator
    const dchar PS = '\u2029'; // UTF paragraph separator

    bool changes = false;
    char[] result = str;
    int column;
    int nspaces;

    foreach ( size_t i, dchar c; str )
    {
        switch ( c )
        {
            case '\t':
                nspaces = tabsize - (column % tabsize);
                if ( !changes )
                {
                    changes = true;
                    result = null;
                    result.length = str.length + nspaces - 1;
                    result.length = i + nspaces;
                    result[0 .. i] = str[0 .. i];
                    result[i .. i + nspaces] = ' ';
                }
                else
                {   auto j = result.length;
                    result.length = j + nspaces;
                    result[j .. j + nspaces] = ' ';
                }
                column += nspaces;
                break;

            case '\r':
            case '\n':
            case PS:
            case LS:
                column = 0;
                goto L1;

            default:
                column++;
            L1:
                if (changes)
                {
                    if (c <= 0x7F)
                        result ~= cast(char)c;
                    else
                    {
                        dchar[1] ca = c;
                        foreach (char ch; ca[])
                            result ~= ch;
                    }
                }
                break;
        }
    }
    return result;
}
