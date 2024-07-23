module core.stdc.stdlib_details;

nothrow:
@nogc:
extern(C):

enum RAND_MAX = 0x7fffffff;

void* aligned_alloc(size_t _align, size_t size);

pragma(LDC_alloca)
void* alloca(size_t size) pure;
