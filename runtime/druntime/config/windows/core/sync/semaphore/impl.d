/**
 * The semaphore module provides a general use semaphore for synchronization.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2009.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Sean Kelly
 * Source:    $(DRUNTIMESRC core/sync/_semaphore.d)
 */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.sync.semaphore.impl;


import core.sync.exception;
import core.time;

version (all)
{
    import core.sys.windows.basetsd /+: HANDLE+/;
    import core.sys.windows.winbase /+: CloseHandle, CreateSemaphoreA, INFINITE,
        ReleaseSemaphore, WAIT_OBJECT_0, WaitForSingleObject+/;
    import core.sys.windows.windef /+: BOOL, DWORD+/;
    import core.sys.windows.winerror /+: WAIT_TIMEOUT+/;
}


class Semaphore
{
    this( uint count = 0 )
    {
        version (all)
        {
            m_hndl = CreateSemaphoreA( null, count, int.max, null );
            if ( m_hndl == m_hndl.init )
                throw new SyncError( "Unable to create semaphore" );
        }
    }


    ~this()
    {
        version (all)
        {
            BOOL rc = CloseHandle( m_hndl );
            assert( rc, "Unable to destroy semaphore" );
        }
    }


    void wait()
    {
        version (all)
        {
            DWORD rc = WaitForSingleObject( m_hndl, INFINITE );
            if ( rc != WAIT_OBJECT_0 )
                throw new SyncError( "Unable to wait for semaphore" );
        }
    }


    bool wait( Duration period )
    in
    {
        assert( !period.isNegative );
    }
    do
    {
        version (all)
        {
            auto maxWaitMillis = dur!("msecs")( uint.max - 1 );

            while ( period > maxWaitMillis )
            {
                auto rc = WaitForSingleObject( m_hndl, cast(uint)
                                                       maxWaitMillis.total!"msecs" );
                switch ( rc )
                {
                case WAIT_OBJECT_0:
                    return true;
                case WAIT_TIMEOUT:
                    period -= maxWaitMillis;
                    continue;
                default:
                    throw new SyncError( "Unable to wait for semaphore" );
                }
            }
            switch ( WaitForSingleObject( m_hndl, cast(uint) period.total!"msecs" ) )
            {
            case WAIT_OBJECT_0:
                return true;
            case WAIT_TIMEOUT:
                return false;
            default:
                throw new SyncError( "Unable to wait for semaphore" );
            }
        }
    }


    void notify()
    {
        version (all)
        {
            if ( !ReleaseSemaphore( m_hndl, 1, null ) )
                throw new SyncError( "Unable to notify semaphore" );
        }
    }


    bool tryWait()
    {
        version (all)
        {
            switch ( WaitForSingleObject( m_hndl, 0 ) )
            {
            case WAIT_OBJECT_0:
                return true;
            case WAIT_TIMEOUT:
                return false;
            default:
                throw new SyncError( "Unable to wait for semaphore" );
            }
        }
    }


protected:

    alias Handle = HANDLE;

    /// Handle to the system-specific semaphore.
    Handle m_hndl;
}
