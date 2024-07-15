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

void lockFile(FILE* flst)
{
    auto fd = fileno(flst);

    version (CRuntime_Bionic)
    {
        import core.sys.bionic.fcntl : LOCK_EX;
        import core.sys.bionic.unistd : flock;
        flock(fd, LOCK_EX); // exclusive lock
    }
    else
        lockf(fd, F_LOCK, 0); // exclusive lock
}
