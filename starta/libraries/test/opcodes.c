#include <stdio.h>
#include <instruction_args.h>
#include <run.h>

char *OPCODES[] = {
    "TEST",
    NULL
};

int test_trace = 0;

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
    if( test_trace ) printf( "%s\t" \
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

int test_trace_on( int trace_flag )
{
    int old_trace_flag = test_trace;
    test_trace = trace_flag;
    return old_trace_flag;
}

/*
 * TEST  Test opcode from external library.
 * 
 */

int TEST( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    printf( "This is the TEST opcode from the \"test.so\" library\n" );

    return 1;
}
