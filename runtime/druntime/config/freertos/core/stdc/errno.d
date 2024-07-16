module core.stdc.errno;

@nogc:
nothrow:

extern(C) extern __gshared int errno;

extern (C) ref int __error()
{
    return errno;
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
