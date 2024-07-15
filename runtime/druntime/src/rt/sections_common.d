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
