///
module core.sync.condition.impl;

import core.sync.mutex: Mutex;
import core.time: Duration;

package enum isImplemented = false;

class Condition
{
    this(Mutex m, size_t capacity = 0) nothrow @safe
    {
        assert(false, "Not implemented");
    }

    this(shared Mutex m, size_t capacity = 0) shared nothrow @safe
    {
        assert(false, "Not implemented");
    }

    final @property Mutex mutex_nothrow() pure nothrow @safe @nogc
    {
        assert(false, "Not implemented");
    }

    void wait() nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    bool wait(Duration dur) nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    bool wait(Duration dur) shared nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    void wait() shared nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    bool tryNotify()
    {
        assert(false, "Not implemented");
    }

    void notify() nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    void notify() shared nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    void notifyAll() nothrow @nogc
    {
        assert(false, "Not implemented");
    }

    void notifyAll() shared nothrow @nogc
    {
        assert(false, "Not implemented");
    }
}
