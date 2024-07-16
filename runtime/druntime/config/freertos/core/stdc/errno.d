module core.stdc.errno;

@nogc:
nothrow:

extern(C) extern __gshared int errno;

//TODO: remove?
extern (C) ref int __error() @system
{
    return errno;
}

ref int fakePureErrno() @nogc nothrow @system
{
    return __error();
}
