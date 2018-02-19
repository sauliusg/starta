
#include <stdio.h>
#include <ctype.h>
#include <instruction_args.h>
#include <run.h>

char *OPCODES[] = {
    "ISINTEGER",
    "ISPRECINT",
    "ISREAL",
    "ISPRECREAL",
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

static int is_integer( char *s );
static int is_integer_with_precision( char *s );
static int is_real( char *s );
static int is_real_with_precision( char *s );

/*
 * ISINTEGER -- Check whether a string contains a (possibly) signed intger.
 * 
 * bytecode:
 * ISINTEGER
 *
 * stack:
 * string -> bool
 */

int ISINTEGER( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[0] );
    int is_int = 0;
    
    TRACE_FUNCTION();
    
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep[0].num.b = is_integer( str );

    return 1;
}

/*
 * ISPRECINT -- Check whether a string contains a (possibly) signed
 *              integer with an optional precision specifier,
 *              e.g. 1234(3).
 * 
 * bytecode:
 * ISPRECINT
 *
 * stack:
 * string -> bool
 */

int ISPRECINT( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[0] );
    int is_int = 0;
    
    TRACE_FUNCTION();
    
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep[0].num.b = is_integer_with_precision( str );

    return 1;
}

/*
 * ISREAL -- Check whether a string contains a real number.
 * 
 * bytecode:
 * ISREAL
 *
 * stack:
 * string -> bool
 */

int ISREAL( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[0] );
    int is_int = 0;
    
    TRACE_FUNCTION();
    
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep[0].num.b = is_real( str );

    return 1;
}

/*
 * ISPRECREAL -- Check whether a string contains a real number.
 * 
 * bytecode:
 * ISPRECREAL
 *
 * stack:
 * string -> bool
 */

int ISPRECREAL( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[0] );
    int is_int = 0;
    
    TRACE_FUNCTION();
    
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep[0].num.b = is_real_with_precision( str );

    return 1;
}

/*
  String check functions:
 */

static int is_integer_with_precision( char *s )
{
    int has_opening_brace = 0;

    if( !s ) return 0;

    if( !isdigit(*s) && *s != '+' && *s != '-' ) {
        return 0;
    }

    if( *s == '+' || *s == '-' ) s++;

    if( !isdigit(*s) ) return 0;

    while( *s && *s != '(' ) {
        if( !isdigit(*s++) ) {
            return 0;
        }
    }

    if( *s && *s != '(' ) return 0;
    if( *s && *s == '(' ) {
        s++;
        has_opening_brace = 1;
    }

    while( *s && *s != ')' ) {
        if( !isdigit(*s++) ) {
            return 0;
        }        
    }

    if( *s != ')' && has_opening_brace ) return 0;
    if( *s == ')' ) s++;

    if( *s != '\0' ) return 0;

    return 1;
}

static int is_integer( char *s )
{
    if( !s ) return 0;

    if( !isdigit(*s) && *s != '+' && *s != '-' ) {
        return 0;
    }

    if( *s == '+' || *s == '-' ) s++;

    if( !isdigit(*s) ) return 0;

    while( *s && *s != '(' ) {
        if( !isdigit(*s++) ) {
            return 0;
        }
    }

    if( *s != '\0' ) return 0;

    return 1;
}

int is_real_with_precision( char *s )
{
    int has_decimal = 0, has_digits = 0;

    if( !s || !*s ) return 0;

    if( !isdigit(*s) && *s != '+' && *s != '-' && *s != '.' ) {
        return 0;
    }

    if( *s == '+' || *s == '-' ) s++;

    /* decimal point may follow the sign, as in +.0123 */
    if( *s == '.' ) {
        s ++;
        has_decimal = 1;
    }

    if( !isdigit(*s) ) return 0;

    while( isdigit(*s) ) {
        s++;
        has_digits = 1;
    }

    if( *s == '.' ) {
        if( has_decimal ) {
            return 0;
        } else {
            has_decimal = 1;
            s ++;
        }
    }

    while( isdigit(*s) ) {
        s++;
        has_digits = 1;
    }

    if( !has_digits ) return 0;

    /* Integers count as reals: */
    if( *s == '\0' ) return 1;

    if( *s != '(' &&
        *s != 'E' && *s != 'e' &&
        *s != 'D' && *s != 'd' /* Fortranish :) */
        ) {
        return 0;
    }

    if( *s == 'E' || *s == 'e' ||
        *s == 'D' || *s == 'd' ) {
        s ++;
        if( *s == '+' || *s == '-' ) s++;
        if( !isdigit(*s) ) {
            return 0;
        }
        while( isdigit(*s) ) s++;
    }

    if( *s == '\0' ) return 1;
    if( *s != '(' )
        return 0;
    else
        s++;
    if( !isdigit(*s) ) return 0;
    while( isdigit(*s) ) s++;
    if( *s != ')' ) return 0;
    s++;
    if( *s != '\0' ) return 0;

    return 1;
}

int is_real( char *s )
{
    int has_decimal = 0, has_digits = 0;

    if( !s || !*s ) return 0;

    if( !isdigit(*s) && *s != '+' && *s != '-' && *s != '.' ) {
        return 0;
    }

    if( *s == '+' || *s == '-' ) s++;

    /* decimal point may follow the sign, as in +.0123 */
    if( *s == '.' ) {
        s ++;
        has_decimal = 1;
    }

    if( !isdigit(*s) ) return 0;

    while( isdigit(*s) ) {
        s++;
        has_digits = 1;
    }

    if( *s == '.' ) {
        if( has_decimal ) {
            return 0;
        } else {
            has_decimal = 1;
            s ++;
        }
    }

    while( isdigit(*s) ) {
        s++;
        has_digits = 1;
    }

    if( !has_digits ) return 0;

    /* Integers count as reals: */
    if( *s == '\0' ) return 1;

    if( *s != '(' &&
        *s != 'E' && *s != 'e' &&
        *s != 'D' && *s != 'd' /* Fortranish :) */
        ) {
        return 0;
    }

    if( *s == 'E' || *s == 'e' ||
        *s == 'D' || *s == 'd' ) {
        s ++;
        if( *s == '+' || *s == '-' ) s++;
        if( !isdigit(*s) ) {
            return 0;
        }
        while( isdigit(*s) ) s++;
    }

    if( *s != '\0' ) return 0;

    return 1;
}
