/**
 *
 * Copyright: Copyright Digital Mars 2000 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Walter Bright, Sean Kelly, Martin Nowak
 * Source: $(DRUNTIMESRC rt/_sections.d)
 */

module rt.sections_common;

import rt.deh, rt.minfo;

template isSectionGroup(T)
{
    enum isSectionGroup =
        is(typeof(T.init.modules) == immutable(ModuleInfo*)[]) &&
        is(typeof(T.init.moduleGroup) == ModuleGroup) &&
        (!is(typeof(T.init.ehTables)) || is(typeof(T.init.ehTables) == immutable(FuncTable)[])) &&
        is(typeof(T.init.gcRanges) == void[][]) &&
        is(typeof({ foreach (ref T; T) {}})) &&
        is(typeof({ foreach_reverse (ref T; T) {}}));
}

import rt.sections;

static assert(isSectionGroup!(SectionGroup));
static assert(is(typeof(&initSections) == void function() nothrow @nogc));
static assert(is(typeof(&finiSections) == void function() nothrow @nogc));
static assert(is(typeof(&initTLSRanges) RT == return) &&
              is(typeof(&initTLSRanges) == RT function() nothrow @nogc) &&
              is(typeof(&finiTLSRanges) == void function(RT) nothrow @nogc) &&
              is(typeof(&scanTLSRanges) == void function(RT, scope void delegate(void*, void*) nothrow) nothrow));

bool scanDataSegPrecisely() nothrow @nogc
{
    import rt.config;
    string opt = rt_configOption("scanDataSeg");
    switch (opt)
    {
        case "":
        case "conservative":
            return false;
        case "precise":
            return true;
        default:
            __gshared err = new Error("DRT invalid scanDataSeg option, must be 'precise' or 'conservative'");
            throw err;
    }
}
