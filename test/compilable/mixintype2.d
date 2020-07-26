
alias fun = mixin("(){}");

void test1()
{
    int x = 1;
    static immutable c = 2;

    fun();
    foo!(mixin("int"))();
    foo!(mixin("long*"))();
    foo!(mixin("ST!(int, S.T)"))();
    foo!(mixin(ST!(int, S.T)))();

    int[mixin("string")] a1;
    int[mixin("5")] a2;
    int[mixin("c")] a3;
    int[] v1 = new int[mixin("3")];
    auto v2 = new int[mixin("x")];

    mixin(q{__traits(getMember, S, "T")}) ftv;

    alias T = int*;
    static assert(__traits(compiles, mixin("int")));
    static assert(__traits(compiles, mixin(q{int[mixin("string")]})));
    static assert(__traits(compiles, mixin(q{int[mixin("2")]})));
    static assert(__traits(compiles, mixin(T)));
    static assert(__traits(compiles, mixin("int*")));
    static assert(__traits(compiles, mixin(typeof(0))));
}

struct S { alias T = float*; }

struct ST(X,Y) {}

void foo(alias t)() {}

/**************************************************/
// https://issues.dlang.org/show_bug.cgi?id=21074

alias Byte = ubyte;
alias Byte2(A) = ubyte;
alias T0 = mixin(q{const(Byte)})*;
alias T1 = mixin(q{const(Byte[1])})*;
alias T2 = mixin(q{const(Byte2!int)})*;
alias T3 = mixin(q{const(mixin(Byte2!int))})*;
alias T4 = mixin(q{const(mixin("__traits(getMember, S, \"T\")"))})*;
alias T5 = const(mixin(q{Byte}))*;
alias T6 = const(mixin(q{immutable(Byte)}))*;
alias T7 = const(mixin(q{shared(Byte)}))*;

// the following tests now work
static assert(is(T0 == const(ubyte)*));
static assert(is(T1 == const(ubyte[1])*));
static assert(is(T2 == const(ubyte)*));
static assert(is(T3 == const(ubyte)*));
static assert(is(T4 == const(float*)*));
static assert(is(T5 == const(ubyte)*));
static assert(is(T6 == immutable(ubyte)*));
static assert(is(T7 == const(shared(ubyte))*));

// this doesn't work but I'll file a new issue
/*
alias T8 = mixin(q{immutable(__traits(getMember, S, "T"))})*;
static assert(is(T8 == immutable(float*)*));
*/
