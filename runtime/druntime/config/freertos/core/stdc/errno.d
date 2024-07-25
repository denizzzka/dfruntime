module core.stdc.errno;

@nogc:
nothrow:

extern(C)
pragma(mangle, "errno") // picolibc
extern __gshared int errno_var;

//TODO: Phobos: revert corresponding safe->trusted change
extern (C) ref int errno() @trusted => errno_var;

extern (C) ref int __error()
{
    return errno_var;
}

private auto assumeFakeAttributesRefReturn(T)(T t) @trusted
{
    import core.internal.traits : Parameters, ReturnType;
    alias RT = ReturnType!T;
    alias P = Parameters!T;
    alias type = ref RT function(P) pure @nogc nothrow;
    return cast(type) t;
}

ref int fakePureErrno() pure
{
    return assumeFakeAttributesRefReturn(&__error)();
}

//TODO: move to picolibc tag:
enum EAGAIN = 11;
