/**
 * The fiber module provides lightweight threads aka fibers.
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/core/thread/fiber/package.d)
 */
module core.thread.fiber;

import core.exception : onOutOfMemoryError;
import core.memory: pageSize;
import core.stdc.stdlib: malloc, free;
import core.thread.threadbase: ThreadBase;
import core.thread.context: StackContext;
import core.thread.fiber.base: FiberBase;
import core.thread.stack: isStackGrowingDown;
version (LDC) import ldc.attributes;

extern(C) void fiber_entryPoint() nothrow;

static assert(isStackGrowingDown);

version (ARM)
    version = InitStackWorks;
else version (RISCV32)
    version = InitStackWorks;

version (InitStackWorks)
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

version (all) //TODO: Why this code is not generalized?
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
    in(m_ctxt)
    {
        .initStack(m_ctxt);
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

version (RISCV32)
package extern (C) void fiber_switchContext( void** oldp, void* newp ) nothrow @nogc
{
    assert(false, "FIXME: fiber_switchContext not implemented");
}
else
package extern (C) void fiber_switchContext( void** oldp, void* newp ) nothrow @nogc;
