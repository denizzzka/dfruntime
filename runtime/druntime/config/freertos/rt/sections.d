/**
 * FreeRTOS rt.sections implementation
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/rt/sections.d)
 */

module rt.sections;

version (LDC):

public import rt.sections_ldc;
import freertos = internal.binding;

debug(PRINTF) import core.stdc.stdio : printf;

// These values described in linker script
extern(C) extern __gshared void* _data;
extern(C) extern __gshared void* _ebss;

extern(C) extern __gshared void* _tdata;
extern(C) extern __gshared void* _tdata_size;
extern(C) extern __gshared void* _tbss;
extern(C) extern __gshared void* _tbss_size;

struct TLSParams
{
    void* tdata_start;
    size_t tdata_size;
    void* tbss_start;
    size_t tbss_size;
    size_t full_tls_size;
}

TLSParams getTLSParams() nothrow @nogc
{
    auto tdata_start = cast(void*)&_tdata;
    auto tbss_start = cast(void*)&_tbss;
    size_t tdata_size = cast(size_t)&_tdata_size;
    size_t tbss_size = cast(size_t)&_tbss_size;
    size_t full_tls_size = tdata_size + tbss_size;

    assert(tbss_size > 1);

    return TLSParams(
        tdata_start,
        tdata_size,
        tbss_start,
        tbss_size,
        full_tls_size
    );
}

void fillGlobalSectionGroup(ref SectionGroup gsg) nothrow @nogc
{
    debug(PRINTF) printf(__FUNCTION__~" called\n");

    // Writeable (non-TLS) data sections covered by GC
    auto data_start = cast(void*)&_data;
    ptrdiff_t size = cast(void*)&_ebss - data_start;

    gsg._gcRanges.insertBack(data_start[0 .. size]);

    debug(PRINTF) printf(__FUNCTION__~" done\n");
}

void finiTLSRanges(void[] rng) nothrow @nogc
{
    import core.stdc.stdlib: free;

    debug(PRINTF) printf("finiTLSRanges called\n");

    assert(read_tp_secondary() !is null);

    free(rng.ptr);
}

package void* read_tp_secondary() nothrow @nogc
{
    return freertos.pvTaskGetThreadLocalStoragePointer(null, 0);
}

void ctorsDtorsWarning() nothrow
{
    assert(false, "Deprecation 16211");
/*
    fprintf(stderr, "Deprecation 16211 warning:\n"
        ~ "A cycle has been detected in your program that was undetected prior to DMD\n"
        ~ "2.072. This program will continue, but will not operate when using DMD 2.074\n"
        ~ "to compile. Use runtime option --DRT-oncycle=print to see the cycle details.\n");
 */
}

version(ARM)
{

import core.stdc.stdlib: aligned_alloc;
import core.memory: GC;

private enum TCB_size = 8; // ARM EABI specific

/***
 * Called once per thread; returns array of thread local storage ranges
 */
void[] initTLSRanges() nothrow @nogc
{
    debug(PRINTF) printf("external initTLSRanges called\n");

    debug
    {
        assert(__aeabi_read_tp() is null, "TLS already initialized?");
    }

    auto p = getTLSParams();

    // TLS
    import core.stdc.string: memcpy, memset;

    void* tls = aligned_alloc(8, p.full_tls_size);
    assert(tls, "cannot allocate TLS block");

    // Copying TLS data
    memcpy(tls, p.tdata_start, p.tdata_size);

    // Init local bss by zeroes
    memset(tls + p.tdata_size, 0x00, p.tbss_size);

    freertos.vTaskSetThreadLocalStoragePointer(null, 0, tls - TCB_size /* ARM EABI specific offset */);

    debug
    {
        void* tls_arm = __aeabi_read_tp();
        assert(tls - tls_arm == TCB_size);
    }

    // Register in GC
    //TODO: move this info into our own SectionGroup implementation?
    GC.addRange(tls, p.full_tls_size);

    return tls[0 .. p.full_tls_size];
}

extern(C) extern void* __aeabi_read_tp() nothrow @nogc
{
    return read_tp_secondary();
}

}
else version (RISCV32)
{

import core.stdc.stdlib: aligned_alloc;
import core.memory: GC;

/***
 * Called once per thread; returns array of thread local storage ranges
 */
void[] initTLSRanges() nothrow @nogc
{
    debug(PRINTF) printf("external initTLSRanges called\n");

    debug
    {
        assert(read_tp_secondary() is null, "TLS already initialized?");
    }

    auto p = getTLSParams();

    // TLS
    import core.stdc.string: memcpy, memset;

    void* tls = aligned_alloc(8, p.full_tls_size);
    assert(tls, "cannot allocate TLS block");

    // Copying TLS data
    memcpy(tls, p.tdata_start, p.tdata_size);

    // Init local bss by zeroes
    memset(tls + p.tdata_size, 0x00, p.tbss_size);

    freertos.vTaskSetThreadLocalStoragePointer(null, 0, tls);

    // Register in GC
    //TODO: move this info into our own SectionGroup implementation?
    GC.addRange(tls, p.full_tls_size);

    return tls[0 .. p.full_tls_size];
}

}
