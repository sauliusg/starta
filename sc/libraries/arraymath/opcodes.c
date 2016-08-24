
#include <stdio.h>
#include <math.h>
#include <stackcell.h>
#include <alloccell.h>
#include <run.h>

char *OPCODES[] = {

#include "locally-generated/int_arrays.tab.c"
#include "locally-generated/long_arrays.tab.c"
#include "locally-generated/llong_arrays.tab.c"

#include "locally-generated/float_arrays.tab.c"
#include "locally-generated/double_arrays.tab.c"
#include "locally-generated/ldouble_arrays.tab.c"

#include "locally-generated/byte_iarrays.tab.c"
#include "locally-generated/short_iarrays.tab.c"
#include "locally-generated/int_iarrays.tab.c"
#include "locally-generated/long_iarrays.tab.c"
#include "locally-generated/llong_iarrays.tab.c"

#include "locally-generated/byte_farrays.tab.c"
#include "locally-generated/short_farrays.tab.c"
#include "locally-generated/int_farrays.tab.c"
#include "locally-generated/long_farrays.tab.c"
#include "locally-generated/llong_farrays.tab.c"

#include "locally-generated/float_farrays.tab.c"
#include "locally-generated/double_farrays.tab.c"
#include "locally-generated/ldouble_farrays.tab.c"

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

#include <locally-generated/int_arrays.c>
#include <locally-generated/long_arrays.c>
#include <locally-generated/llong_arrays.c>

#include <locally-generated/float_arrays.c>
#include <locally-generated/double_arrays.c>
#include <locally-generated/ldouble_arrays.c>

#include <locally-generated/byte_iarrays.c>
#include <locally-generated/short_iarrays.c>
#include <locally-generated/int_iarrays.c>
#include <locally-generated/long_iarrays.c>
#include <locally-generated/llong_iarrays.c>

#include <locally-generated/byte_farrays.c>
#include <locally-generated/short_farrays.c>
#include <locally-generated/int_farrays.c>
#include <locally-generated/long_farrays.c>
#include <locally-generated/llong_farrays.c>

#include <locally-generated/float_farrays.c>
#include <locally-generated/double_farrays.c>
#include <locally-generated/ldouble_farrays.c>
