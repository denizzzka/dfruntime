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
//TODO: swap names like _edata to _data_end
version (ESP_IDF)
 {
    pragma(mangle, "_data_start")
    extern(C) extern __gshared void* _data;

    pragma(mangle, "_data_end")
    extern(C) extern __gshared void* _edata;

    pragma(mangle, "_bss_start")
    extern(C) extern __gshared void* _bss;

    pragma(mangle, "_bss_end")
    extern(C) extern __gshared void* _ebss;

    private struct SecHdr { char unused; }

    extern(C) extern __gshared SecHdr
        _thread_local_data_start,
        _thread_local_data_end,
        _thread_local_bss_start,
        _thread_local_bss_end;
}
else
{
    extern(C) extern __gshared void* _data;
    //~ extern(C) extern __gshared void* _edata;
    //~ extern(C) extern __gshared void* _bss;
    extern(C) extern __gshared void* _ebss;
    extern(C) extern __gshared void* _tdata;
    extern(C) extern __gshared void* _tdata_size;
    extern(C) extern __gshared void* _tbss;
    extern(C) extern __gshared void* _tbss_size;
}

struct TLSParams
{
    void* tdata_start;
    size_t tdata_size;
    void* tbss_start;
    size_t tbss_size;
    size_t full_tls_size;
}

version (ESP_IDF) {} else
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
    version (ESP_IDF)
    {
        {
            auto data_start = cast(void*)&_data;
            ptrdiff_t size = cast(void*)&_edata - data_start;
            gsg._gcRanges.insertBack(data_start[0 .. size]);
        }

        {
            auto bss_start = cast(void*)&_bss;
            ptrdiff_t size = cast(void*)&_ebss - bss_start;
            gsg._gcRanges.insertBack(bss_start[0 .. size]);
        }
    }
    else
    {
        //FIXME: split _data and _bss and remove version (ESP_IDF) above
        auto data_start = cast(void*)&_data;
        ptrdiff_t size = cast(void*)&_ebss - data_start;

        gsg._gcRanges.insertBack(data_start[0 .. size]);
    }

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
    version (ESP_IDF)
        enum idx = 1; // index 0 is reserved for ESP-IDF internal uses
    else
        enum idx = 0;

    return freertos.pvTaskGetThreadLocalStoragePointer(null, idx);
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

import core.memory: GC;
import core.stdc.stdlib: aligned_alloc;

version(ARM)
{

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
else version (ESP_IDF)
{

void[] initTLSRanges() nothrow @nogc
{
    assert(read_tp_secondary() is null, "TLS already initialized?");

    assert(&_thread_local_data_start < &_thread_local_data_end);
    assert(&_thread_local_bss_start < &_thread_local_bss_end);

    // Calculate TLS area size and round up to multiple of 16 bytes.
    const tls_data_size = &_thread_local_data_end - &_thread_local_data_start;
    const tls_bss_size = &_thread_local_bss_end - &_thread_local_bss_start;

    // TODO: round up tls_area_size to multiple of 16 bytes
    const tls_area_size = tls_data_size + tls_bss_size + 16;

    assert(tls_data_size >= 0);
    assert(tls_bss_size >= 0);
    assert(tls_area_size >= 0);

    // TLS
    import core.stdc.string: memcpy, memset;

    void* tls = aligned_alloc(16, tls_area_size);
    assert(tls, "cannot allocate TLS block");

    // Copying TLS data
    memcpy(tls, &_thread_local_data_start, tls_data_size);

    // Init local bss by zeroes
    memset(tls + tls_data_size, 0x00, tls_bss_size);

    freertos.vTaskSetThreadLocalStoragePointer(null, 1, tls);

    // Register in GC
    GC.addRange(tls, tls_area_size);

    return tls[0 .. tls_area_size];
}

}
