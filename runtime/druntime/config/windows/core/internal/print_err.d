module core.internal.print_err;

import core.sys.windows.winbase : GetStdHandle, STD_ERROR_HANDLE, WriteFile, INVALID_HANDLE_VALUE;

package void writeStr(scope const(char)[][] m...) @nogc nothrow @trusted
{
    auto h = GetStdHandle(STD_ERROR_HANDLE);

    if (h == INVALID_HANDLE_VALUE)
    {
        // attempt best we can to print the message

        /* Note that msg is scope.
         * assert() calls _d_assert_msg() calls onAssertErrorMsg() calls _assertHandler() but
         * msg parameter isn't scope and can escape.
         * Give up and use our own immutable message instead.
         */
        assert(0, "Cannot get stderr handle for message");
    }

    foreach (s; m)
    {
        assert(s.length <= uint.max);
        WriteFile(h, s.ptr, cast(uint)s.length, null, null);
    }
}
