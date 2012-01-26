
#include <stdio.h>
#include <math.h>
#include <run.h>

char *OPCODES[] = {
    "FCALL",
    "DCALL",
    "LDCALL",
    "FCALL2",
    "DCALL2",
    "LDCALL2",
    "sin",
    "sinf",
    "sinl",
    "cos",
    "cosf",
    "cosl",
    "atan2",
    "atan2f",
    "atan2l",
    "floorf",
    "sqrt",
    "sqrtf",
    "sqrtl",
    "LFLOOR",
    "LFLOORD",
    "LLFLOORLD",

#include "locally-generated/float_float.tab.c"
#include "locally-generated/double_float.tab.c"
#include "locally-generated/ldouble_float.tab.c"

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

#include <locally-generated/float_float.c>
#include <locally-generated/double_float.c>
#include <locally-generated/ldouble_float.c>

/*
 * FCALL 
 * 
 */

int FCALL( INSTRUCTION_FN_ARGS )
{
    float arg = istate.ep[0].num.f; 
    float (*f)(float) = (float (*)(float))istate.code[istate.ip+1].fn;

    TRACE_FUNCTION();

    istate.ep[0].num.f = (*f)( arg );

    return 2;
}

/*
 * DCALL 
 * 
 */

int DCALL( INSTRUCTION_FN_ARGS )
{
    double arg = istate.ep[0].num.d; 
    double (*f)(double) = (double(*)(double))istate.code[istate.ip+1].fn;

    TRACE_FUNCTION();

    istate.ep[0].num.d = (*f)( arg );

    return 2;
}

/*
 * LDCALL 
 * 
 */

int LDCALL( INSTRUCTION_FN_ARGS )
{
    ldouble arg = istate.ep[0].num.ld; 
    ldouble (*f)(ldouble) = (ldouble(*)(ldouble))istate.code[istate.ip+1].fn;

    TRACE_FUNCTION();

    istate.ep[0].num.ld = (*f)( arg );

    return 2;
}

/*
 * FCALL2
 * 
 */

int FCALL2( INSTRUCTION_FN_ARGS )
{
    float arg1 = istate.ep[1].num.f; 
    float arg2 = istate.ep[0].num.f; 
    float (*f)(float,float) =
        (float (*)(float,float))istate.code[istate.ip+1].fn;

    TRACE_FUNCTION();

    istate.ep ++;
    istate.ep[0].num.f = (*f)( arg1, arg2 );

    return 2;
}

/*
 * DCALL2
 * 
 */

int DCALL2( INSTRUCTION_FN_ARGS )
{
    double arg1 = istate.ep[1].num.d; 
    double arg2 = istate.ep[0].num.d; 
    double (*f)(double,double) =
        (double(*)(double,double))istate.code[istate.ip+1].fn;

    TRACE_FUNCTION();

    istate.ep ++;
    istate.ep[0].num.d = (*f)( arg1, arg2 );

    return 2;
}

/*
 * LDCALL2
 * 
 */

int LDCALL2( INSTRUCTION_FN_ARGS )
{
    ldouble arg1 = istate.ep[1].num.ld; 
    ldouble arg2 = istate.ep[0].num.ld; 
    ldouble (*f)(ldouble,ldouble) =
        (ldouble(*)(ldouble,ldouble))istate.code[istate.ip+1].fn;

    TRACE_FUNCTION();

    istate.ep ++;
    istate.ep[0].num.ld = (*f)( arg1, arg2 );

    return 2;
}

/*
 * LFLOOR converts a floating point value on the top of the stack into
 * a long integer number.
 * 
 * bytecode:
 * LFLOOR
 * 
 * stack:
 * float -> long
 * 
 */

int LFLOOR( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.l = (long)floorf( istate.ep[0].num.f );

    return 1;
}

/*
 * LFLOORD converts a double precission floating pooint value on the
 * top of the stack to a long integer number.
 * 
 * bytecode:
 * LFLOORD
 * 
 * stack:
 * double -> long
 * 
 */

int LFLOORD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.l = (long)floor( istate.ep[0].num.d );

    return 1;
}

/*
 * LLFLOORLD converts a long double floating value on the top of the
 * stack into a long long number.
 * 
 * bytecode:
 * LLFLOORLD
 * 
 * stack:
 * ldouble -> llong
 * 
 */

int LLFLOORLD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ll = (long)floor( istate.ep[0].num.ld );

    return 1;
}
