

#include <stdlib.h>
#include <stdio.h>
#include <instruction_args.h>
#include <run.h>

char *OPCODES[] = {
    "SRAND48",
    "DRAND48",
    /* "ERAND48", */
    "LRAND48",
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

/*
 * SRAND48 - this opcode is the initialization function which should
 * be called before using drand48(), lrand48() or mrand48(). The
 * initializer function srand48() sets the high order 32-bits of Xi to
 * the argument seedval.  The low order 16-bits are set to the
 * arbitrary value 0x330E (man drand48(3)).
 * 
 * bytecode:
 * SRAND48
 * 
 * stack:
 * long_seed -->
 */

int SRAND48( INSTRUCTION_FN_ARGS )
{
    long seed = istate.ep[0].num.l;

    TRACE_FUNCTION();

    srand48( seed );
    istate.ep ++;

    return 1;
}

/*
 * DRAND48 - generate uniformly distributed pseudo-random numbers;
 * return non-negative double-precision floating-point values
 * uniformly distributed between [0.0, 1.0).
 * 
 * bytecode:
 * DRAND48
 * 
 * stack:
 * --> double_random
 */

int DRAND48( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0].num.d = drand48();

    return 1;
}

/*
 * LRAND48 - generate uniformly distributed pseudo-random numbers;
 * returns non-negative long integers uniformly distributed between 0
 * and 2^31.
 * 
 * bytecode:
 * LRAND48
 * 
 * stack:
 * --> long_random
 */

int LRAND48( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0].num.l = lrand48();

    return 1;
}
