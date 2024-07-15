/**
 * Contains the implementation for object monitors.
 *
 * Copyright: Copyright Digital Mars 2000 - 2015.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Walter Bright, Sean Kelly, Martin Nowak
 * Source: $(DRUNTIMESRC rt/_monitor_.d)
 */
module rt.monitor_mutex;

package:

version (CRuntime_DigitalMars)
{
    pragma(lib, "snn.lib");
}
import core.sys.windows.winbase /+: CRITICAL_SECTION, DeleteCriticalSection,
    EnterCriticalSection, InitializeCriticalSection, LeaveCriticalSection+/;

alias Mutex = CRITICAL_SECTION;

alias initMutex = InitializeCriticalSection;
alias destroyMutex = DeleteCriticalSection;
alias lockMutex = EnterCriticalSection;
alias unlockMutex = LeaveCriticalSection;

@nogc:
nothrow:

void initMutexesFacility(){}
void destroyMutexesFacility(){}
