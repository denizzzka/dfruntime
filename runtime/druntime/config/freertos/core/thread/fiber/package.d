module core.thread.fiber;

import core.memory: pageSize;
import core.stdc.stdlib: malloc, free;
import core.thread.context: StackContext;
import core.thread.fiber.base: FiberBase;
import core.thread.stack: isStackGrowingDown;
version (LDC) import ldc.attributes;

extern(C) void fiber_entryPoint() nothrow;

static assert(isStackGrowingDown);

version (ARM)
void initStack(StackContext* m_ctxt) nothrow @nogc
{
    void* pstack = m_ctxt.tstack;
    scope(exit) m_ctxt.tstack = pstack;

    void push( size_t val ) nothrow
    {
        pstack -= size_t.sizeof;
        *(cast(size_t*) pstack) = val;
    }

    pstack -= int.sizeof * 8;

    // link register
    push( cast(size_t) &fiber_entryPoint );

    /*
     * We do not push padding and d15-d8 as those are zero initialized anyway
     * Position the stack pointer above the lr register
     */
    pstack += int.sizeof;
}

version (ARM)
class Fiber : FiberBase
{
    enum defaultStackPages = 4;

    this( void function() fn, size_t sz = pageSize * defaultStackPages,
          size_t guardPageSize = pageSize ) nothrow
    {
        super( fn, sz, guardPageSize );
    }

    this( void delegate() dg, size_t sz = pageSize * defaultStackPages,
          size_t guardPageSize = pageSize ) nothrow
    {
        super( dg, sz, guardPageSize );
    }

    final override void allocStack( size_t sz, size_t guardPageSize ) nothrow
    in(!m_pmem)
    in(!m_ctxt)
    {
        sz += pageSize - 1;
        sz -= sz % pageSize;

        m_ctxt = new StackContext;
        m_pmem = malloc( sz );

        if ( !m_pmem )
            onOutOfMemoryError();

        m_ctxt.bstack = m_pmem + sz;
        m_ctxt.tstack = m_pmem + sz;
        void* guard = m_pmem;

        m_size = sz;

        ThreadBase.add( m_ctxt );
    }

    final override void initStack() nothrow @nogc
    {
        initStack(m_ctxt);
    }

    final override void freeStack() nothrow @nogc
    in(m_pmem)
    in(m_ctxt)
    {
        ThreadBase.slock.lock_nothrow();
        scope(exit) ThreadBase.slock.unlock_nothrow();

        ThreadBase.remove( m_ctxt );
        free( m_pmem );

        m_pmem = null;
        m_ctxt = null;
    }
}
