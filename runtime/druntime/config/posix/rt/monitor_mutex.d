/**
 * Contains the implementation for object monitors.
 *
 * Copyright: Copyright Digital Mars 2000 - 2015.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Walter Bright, Sean Kelly, Martin Nowak
 * Source: $(DRUNTIMESRC rt/_monitor_.d)
 */
module rt.monitor_mutex;

package:

import core.atomic, core.stdc.stdlib, core.stdc.string;
import core.sys.posix.pthread;

nothrow:

version (Posix)
{

@nogc:
    alias Mutex = pthread_mutex_t;
    __gshared pthread_mutexattr_t gattr;

    void initMutexesFacility()
    {
        pthread_mutexattr_init(&gattr);
        pthread_mutexattr_settype(&gattr, PTHREAD_MUTEX_RECURSIVE);
    }

    void destroyMutexesFacility()
    {
        pthread_mutexattr_destroy(&gattr);
    }

    void initMutex(pthread_mutex_t* mtx)
    {
        pthread_mutex_init(mtx, &gattr) && assert(0);
    }

    void destroyMutex(pthread_mutex_t* mtx)
    {
        pthread_mutex_destroy(mtx) && assert(0);
    }

    void lockMutex(pthread_mutex_t* mtx)
    {
        pthread_mutex_lock(mtx) && assert(0);
    }

    void unlockMutex(pthread_mutex_t* mtx)
    {
        pthread_mutex_unlock(mtx) && assert(0);
    }
}
else
{
    static assert(0, "Unsupported platform");
}
