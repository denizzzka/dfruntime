module core.stdc.errno;

@nogc:
nothrow:

extern(C) extern __gshared int errno;

extern (C) ref int __error() @system
{
    return errno;
}

ref int fakePureErrno() @nogc nothrow pure @system
{
    return __error();
}
