/**
 * This module provides types and constants used in thread package.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak
 */

module core.thread.types;

/**
 * Represents the ID of a thread, as returned by $(D Thread.)$(LREF id).
 * The exact type varies from platform to platform.
 */
import core.sys.posix.pthread;

alias ThreadID = pthread_t;

struct ll_ThreadData
{
    ThreadID tid;
}

public import core.thread.stack: isStackGrowingDown;

package static immutable size_t PTHREAD_STACK_MIN;

shared static this()
{
    import core.sys.posix.unistd;

    PTHREAD_STACK_MIN = cast(size_t)sysconf(_SC_THREAD_STACK_MIN);
}
