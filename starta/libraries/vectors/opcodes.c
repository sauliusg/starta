
#include <stdio.h>
#include <math.h>
#include <stackcell.h>
#include <alloccell.h>
#include <bcalloc.h>
#include <run.h>
#include <instruction_args.h>
#include <cxprintf.h>

void *module_id = &module_id;

typedef enum {
    VX_VECTOR_NULL = 0,

    VX_VECTOR_LENGTH_ERROR,

    last_VX_VECTOR_ERROR
} vector_error_t;

char *OPCODES[] = {

#include "locally-generated/byte_vectors.tab.c"
#include "locally-generated/short_vectors.tab.c"
#include "locally-generated/int_vectors.tab.c"
#include "locally-generated/long_vectors.tab.c"
#include "locally-generated/llong_vectors.tab.c"

#include "locally-generated/float_vectors.tab.c"
#include "locally-generated/double_vectors.tab.c"
#include "locally-generated/ldouble_vectors.tab.c"

#include "locally-generated/byte_intvect.tab.c"
#include "locally-generated/short_intvect.tab.c"
#include "locally-generated/int_intvect.tab.c"
#include "locally-generated/long_intvect.tab.c"
#include "locally-generated/llong_intvect.tab.c"

#include "locally-generated/float_floatvect.tab.c"
#include "locally-generated/double_floatvect.tab.c"
#include "locally-generated/ldouble_floatvect.tab.c"

    NULL
};

int vectors_trace = 0;

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
    if( vectors_trace ) printf( "%s\t" \
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

int vectors_trace_on( int trace_flag )
{
    int old_trace_flag = vectors_trace;
    vectors_trace = trace_flag;
    return old_trace_flag;
}



#include <locally-generated/byte_vectors.c>
#include <locally-generated/short_vectors.c>
#include <locally-generated/int_vectors.c>
#include <locally-generated/long_vectors.c>
#include <locally-generated/llong_vectors.c>

#include <locally-generated/float_vectors.c>
#include <locally-generated/double_vectors.c>
#include <locally-generated/ldouble_vectors.c>

#include <locally-generated/byte_intvect.c>
#include <locally-generated/short_intvect.c>
#include <locally-generated/int_intvect.c>
#include <locally-generated/long_intvect.c>
#include <locally-generated/llong_intvect.c>

#include <locally-generated/float_floatvect.c>
#include <locally-generated/double_floatvect.c>
#include <locally-generated/ldouble_floatvect.c>
