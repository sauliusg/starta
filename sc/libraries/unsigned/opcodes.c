/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <tcodes.h>

/* uses: */

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stackcell.h>
#include <alloccell.h>
#include <bcalloc.h>
#include <run.h>
#include <cxprintf.h>
#include <bytecode_file.h>

void *module_id = &module_id;

char *OPCODES[] = {

#include "locally-generated/arithm_uint.tab.c"

#include "locally-generated/unsigned_uint.tab.c"

    NULL
};

int trace = 0;

static istate_t *istate_ptr;

#define istate (*istate_ptr)

#ifndef TRACE
#define TRACE
#endif

#if 0
#define EXCEPTION (NULL)
#else
#define EXCEPTION (istate.ex)
#endif

#ifdef TRACE_FUNCTION
#undef TRACE_FUNCTION
#endif

#ifdef TRACE
#define TRACE_FUNCTION() \
    if( trace ) printf( "%s\t" \
                        "%4ld(%9p) %4ld(%9p) " \
                        "%4ld(%9p) %4ld(%9p) " \
                        "%4ld(%9p) %4ld(%9p) ...\n", \
                        __FUNCTION__, \
                        (long)istate.ep[0].num.i, istate.ep[0].PTR, \
                        (long)istate.ep[1].num.i, istate.ep[1].PTR, \
                        (long)istate.ep[2].num.i, istate.ep[2].PTR, \
                        (long)istate.ep[3].num.i, istate.ep[3].PTR, \
                        (long)istate.ep[4].num.i, istate.ep[4].PTR, \
                        (long)istate.ep[5].num.i, istate.ep[5].PTR )
#else
#define TRACE_FUNCTION()
#endif

#define BC_CHECK_PTR( ptr ) \
    if( !(ptr) ) { \
        bc_merror( EXCEPTION ); \
        return 0; \
    }

int init( istate_t *global_istate )
{
    istate_ptr = global_istate;
    return 0;
}

int trace_on( int trace_flag )
{
    int old_trace_flag = trace;
    trace = trace_flag;
    return old_trace_flag;
}

#include <locally-generated/unsigned_uint.c>

#include <locally-generated/arithm_uint.c>
