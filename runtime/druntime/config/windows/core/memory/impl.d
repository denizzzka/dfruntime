module core.memory.impl;

package size_t pageSize()
{
    import core.sys.windows.winbase : GetSystemInfo, SYSTEM_INFO;

    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return cast(size_t) si.dwPageSize;
}
