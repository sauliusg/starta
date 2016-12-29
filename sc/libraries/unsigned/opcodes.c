/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <opcodes.h>

/* uses: */

#include <stdio.h>
#include <string.h>
#include <limits.h> /* for the ..._MAX constants */
#include <errno.h>
#include <assert.h>
#include <stackcell.h>
#include <alloccell.h>
#include <bcalloc.h>
#include <run.h>
#include <cxprintf.h>
#include <bytecode_file.h>

void *module_id = &module_id;

char *OPCODES[] = {

#include "locally-generated/unsigned_ubyte.tab.c"
#include "locally-generated/unsigned_ushort.tab.c"
#include "locally-generated/unsigned_uint.tab.c"
#include "locally-generated/unsigned_ulong.tab.c"
#include "locally-generated/unsigned_ullong.tab.c"

#include "locally-generated/opcodes.tab.c"

    NULL
};

/* If 'strict_unsigned_conversions' is true, the UI2L opcodes will
   never convert an unsigned value to an integer value if the signed
   value is the same size or smaller. If 'strict_unsigned_conversions'
   is false, the opcodes will convert an unsigned value into a signed
   value if the value fits the destination.

   Users will prefer the 'strict_unsigned_conversions = 0' (false),
   but developers might find it easier to test software when
   'strict_unsigned_conversions = 1' (true) is set.

   USE the 'STRICT' opcode from this library to set and query the
   'strict_unsigned_conversions' flag. */

static int strict_unsigned_conversions = 0;

int trace = 0;

istate_t *istate_ptr;

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

/*
 * Setting flags
 */

/*
 * STRICT  Set and query the 'strict_unsigned_conversions' flag.
 *
 * bytecode:
 * STRICT
 *
 * stack:
 * bool -> bool
*/

int STRICT( INSTRUCTION_FN_ARGS )
{
    unsigned char strict = istate.ep[0].num.c;

    TRACE_FUNCTION();

    istate.ep[0].num.c = strict_unsigned_conversions;
    strict_unsigned_conversions = strict;

    return 1;
}

/*
** Type conversion opcodes:
*/

/*
 * UBEXTEND converts unsigned byte value on the top of the stack to
 * short unsigned integer
 * 
 * bytecode:
 * UBEXTEND
 * 
 * stack:
 * ubyte (char) -> ushort
 * 
 */

int UBEXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.us = istate.ep[0].num.c;

    return 1;
}

/*
 * UEXTEND converts unsigned integer value on the top of the stack to
 * unsignde long integer
 * 
 * bytecode:
 * UEXTEND
 * 
 * stack:
 * uint -> ulong
 * 
 */

int UEXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ul = istate.ep[0].num.ui;

    return 1;
}

/*
 * UHEXTEND converts unsigned short integer value on the top of the
 * stack into unsigned integer
 * 
 * bytecode:
 * UHEXTEND
 * 
 * stack:
 * ushort -> uint
 * 
 */

int UHEXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ui = istate.ep[0].num.us;

    return 1;
}

/*
 * ULEXTEND converts unsigned long integer value on the top of the
 * stack to a unsigned long long integer
 * 
 * bytecode:
 * ULEXTEND
 * 
 * stack:
 * ulong -> ullong
 * 
 */

int ULEXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ull = istate.ep[0].num.ul;

    return 1;
}

/* Unsigned -> signed conversions: you can always convert an unsigned
   integer to a signed integer of larger size: */

/* Type size checks: */

#define CHECK_SIZES( DST_TYPE, SRC_TYPE, DST_VAL, SRC_VAL ) \
    if( strict_unsigned_conversions ) {                                     \
        if( sizeof(DST_VAL) <= sizeof(SRC_VAL) ) {                          \
            interpret_raise_exception_with_bcalloc_message                  \
                ( /* err_code = */ -3,                                      \
                  /* message = */ (char*)cxprintf                           \
                  ( "%s - the target type '" #DST_TYPE                      \
                    "' (%d bytes) is not larger "                           \
                    "than the original '" #SRC_TYPE "' (%d bytes)",         \
                    __FUNCTION__,                                           \
                    sizeof(DST_VAL), sizeof(SRC_VAL) ),                     \
                  /* module_id = */ 0,                                      \
                  /* exception_id = */ SL_EXCEPTION_TRUNCATED_INTEGER,      \
                  EXCEPTION );                                              \
            return 0;                                                       \
        }                                                                   \
    } else {                                                                \
          if( SRC_VAL > ( ((unsigned DST_TYPE)((DST_TYPE)-1)) >> 1 ) ) {    \
            interpret_raise_exception_with_bcalloc_message                  \
                ( /* err_code = */ -3,                                      \
                  /* message = */ (char*)cxprintf                           \
                  ( "%s - " #SRC_TYPE " value '%u' does not fit '"          \
                    #DST_TYPE "' value",                                    \
                    __FUNCTION__, SRC_VAL ),                                \
                  /* module_id = */ 0,                                      \
                  /* exception_id = */ SL_EXCEPTION_TRUNCATED_INTEGER,      \
                  EXCEPTION );                                              \
            return 0;                                                       \
        }                                                                   \
    }

/*
 * UB2S convert unsigned byte to short integer.
 * 
 * bytecode:
 * UB2S
 * 
 * stack:
 * ubyte -> short
 * 
 */

int UB2S( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    /* The ..._MAX constants come from the 'limits.h' */
#if SHRT_MAX < UCHAR_MAX
    CHECK_SIZES( short, unsigned char, istate.ep[0].num.s, istate.ep[0].num.c );
#endif

    istate.ep[0].num.s = istate.ep[0].num.c;

    return 1;
}

/*
 * US2I convert unsigned short to integer.
 * 
 * bytecode:
 * US2I
 * 
 * stack:
 * ushort -> int
 * 
 */

int US2I( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

#if INT_MAX < USHRT_MAX
    CHECK_SIZES( int, unsigned short, istate.ep[0].num.i, istate.ep[0].num.us );
#endif

    istate.ep[0].num.i = istate.ep[0].num.us;

    return 1;
}

/*
 * UI2L convert unsigned int to long.
 * 
 * bytecode:
 * UI2L
 * 
 * stack:
 * uint -> long
 * 
 */

int UI2L( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

#if LONG_MAX < UINT_MAX
    CHECK_SIZES( long, unsigned int, istate.ep[0].num.l, istate.ep[0].num.ui );
#endif

    istate.ep[0].num.l = istate.ep[0].num.ui;

    return 1;
}

/*
 * UL2LL convert unsigned long to long long.
 * 
 * bytecode:
 * UL2LL
 * 
 * stack:
 * ulong -> llong
 * 
 */

int UL2LL( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

#if LLONG_MAX < ULONG_MAX
    CHECK_SIZES( long long, unsigned long, istate.ep[0].num.ll, istate.ep[0].num.ul );
#endif

    istate.ep[0].num.ll = istate.ep[0].num.ul;

    return 1;
}

#include <locally-generated/unsigned_ubyte.c>
#include <locally-generated/unsigned_ushort.c>
#include <locally-generated/unsigned_uint.c>
#include <locally-generated/unsigned_ulong.c>
#include <locally-generated/unsigned_ullong.c>
