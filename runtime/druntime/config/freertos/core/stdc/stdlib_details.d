module core.stdc.stdlib_details;

nothrow @nogc:

enum RAND_MAX = 0x7fffffff;

extern(C) void* aligned_alloc(size_t _align, size_t size);
