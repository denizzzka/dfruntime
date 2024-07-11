/**
 * This module provides types and constants used in thread package.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak
 * Source:    $(DRUNTIMESRC core/thread/osthread.d)
 */

module core.thread.types;

alias ThreadID = uint;

struct ll_ThreadData
{
    ThreadID tid;
    void delegate() nothrow cbDllUnload;
}

public import core.thread.stack: isStackGrowingDown;
