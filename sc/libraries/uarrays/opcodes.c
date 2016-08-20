
#include <stdio.h>
#include <limits.h> /* for the ..._MAX constants */
#include <math.h>
#include <stackcell.h>
#include <alloccell.h>
#include <run.h>
#include <arrays.h>

char *OPCODES[] = {

#include <locally-generated/opcodes.tab.c>

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

/* Unsigned array to signed array conversion opcodes: */

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

#ifndef ARRAY_ELEMENT
#error ARRAY_ELEMENT unset! Please check if 'arrays.h' from the interpreter dir is included.
#endif

/*
 * ARRAY_UB2I convert unsigned byte array to integer array.
 * 
 * bytecode:
 * ARRAY_UB2I
 * 
 * stack:
 * int array, ubyte array -> int array
 * 
 */

int ARRAY_UB2I( INSTRUCTION_FN_ARGS )
{
    ssize_t i, length;
#ifdef packed_type
    unsigned char *src_array = STACKCELL_PTR( istate.ep[0] );
    int *dst_array = STACKCELL_PTR( istate.ep[1] );
#elif full_stackcell
    stackcell_t *src_array = STACKCELL_PTR( istate.ep[0] );
    stackcell_t *dst_array = STACKCELL_PTR( istate.ep[1] );
#elif split_stackcell
    stackunion_t *src_array = STACKCELL_PTR( istate.ep[0] );
    stackunion_t *dst_array = STACKCELL_PTR( istate.ep[1] );
#endif
    alloccell_t *src_hdr = (alloccell_t*)src_array;
    alloccell_t *dst_hdr = (alloccell_t*)dst_array;

    TRACE_FUNCTION();

    if( src_array && dst_array ) {
        length = src_hdr[-1].length < dst_hdr[-1].length ?
            src_hdr[-1].length : dst_hdr[-1].length;

        for( i = 0; i < length; i++ ) {
#if INT_MAX < UCHAR_MAX
            CHECK_SIZES( int, unsigned char, 
                         ARRAY_ELEMENT(dst_array[i]),
                         ARRAY_ELEMENT(src_array[i]) );
#endif
#ifdef packed_type
            dst_array[i] = src_array[i];
#elif full_stackcell
            dst_array[i].num.i = src_array[i].num.c;
#elif split_stackcell
            dst_array[i].i = src_array[i].c;
#endif
        }
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep++;

    return 1;
}

/*
 * ARRAY_US2I convert unsigned short array to integer array.
 * 
 * bytecode:
 * ARRAY_US2I
 * 
 * stack:
 * int array, ushort array -> int array
 * 
 */

int ARRAY_US2I( INSTRUCTION_FN_ARGS )
{
    ssize_t i, length;
#ifdef packed_type
    unsigned short *src_array = STACKCELL_PTR( istate.ep[0] );
    int *dst_array = STACKCELL_PTR( istate.ep[1] );
#elif full_stackcell
    stackcell_t *src_array = STACKCELL_PTR( istate.ep[0] );
    stackcell_t *dst_array = STACKCELL_PTR( istate.ep[1] );
#elif split_stackcell
    stackunion_t *src_array = STACKCELL_PTR( istate.ep[0] );
    stackunion_t *dst_array = STACKCELL_PTR( istate.ep[1] );
#endif
    alloccell_t *src_hdr = (alloccell_t*)src_array;
    alloccell_t *dst_hdr = (alloccell_t*)dst_array;

    TRACE_FUNCTION();

    if( src_array && dst_array ) {
        length = src_hdr[-1].length < dst_hdr[-1].length ?
            src_hdr[-1].length : dst_hdr[-1].length;

        for( i = 0; i < length; i++ ) {
#if INT_MAX < USHRT_MAX
            CHECK_SIZES( int, unsigned short, 
                         ARRAY_ELEMENT(dst_array[i]),
                         ARRAY_ELEMENT(src_array[i]) );
#endif
#ifdef packed_type
            dst_array[i] = src_array[i];
#elif full_stackcell
            dst_array[i].num.i = src_array[i].num.us;
#elif split_stackcell
            dst_array[i].i = src_array[i].us;
#endif
        }
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep++;

    return 1;
}

/*
 * ARRAY_UI2L convert unsigned integer array to a 'long int' array.
 * 
 * bytecode:
 * ARRAY_UI2L
 * 
 * stack:
 * long array, uint array -> long array
 * 
 */

int ARRAY_UI2L( INSTRUCTION_FN_ARGS )
{
    ssize_t i, length;
#ifdef packed_type
    unsigned int *src_array = STACKCELL_PTR( istate.ep[0] );
    long *dst_array = STACKCELL_PTR( istate.ep[1] );
#elif full_stackcell
    stackcell_t *src_array = STACKCELL_PTR( istate.ep[0] );
    stackcell_t *dst_array = STACKCELL_PTR( istate.ep[1] );
#elif split_stackcell
    stackunion_t *src_array = STACKCELL_PTR( istate.ep[0] );
    stackunion_t *dst_array = STACKCELL_PTR( istate.ep[1] );
#endif
    alloccell_t *src_hdr = (alloccell_t*)src_array;
    alloccell_t *dst_hdr = (alloccell_t*)dst_array;

    TRACE_FUNCTION();

    if( src_array && dst_array ) {
        length = src_hdr[-1].length < dst_hdr[-1].length ?
            src_hdr[-1].length : dst_hdr[-1].length;

        for( i = 0; i < length; i++ ) {
#if LONG_MAX < UINT_MAX
            CHECK_SIZES( long, unsigned int, 
                         ARRAY_ELEMENT(dst_array[i]),
                         ARRAY_ELEMENT(src_array[i]) );
#endif
#ifdef packed_type
            dst_array[i] = src_array[i];
#elif full_stackcell
            dst_array[i].num.l = src_array[i].num.ui;
#elif split_stackcell
            dst_array[i].l = src_array[i].ui;
#endif
        }
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep++;

    return 1;
}
