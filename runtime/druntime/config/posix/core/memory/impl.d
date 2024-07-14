module core.memory.impl;

package size_t pageSize()
{
    import core.sys.posix.unistd : sysconf, _SC_PAGESIZE;

    return cast(size_t) sysconf(_SC_PAGESIZE);
}
