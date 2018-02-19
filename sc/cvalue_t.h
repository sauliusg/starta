/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __CVALUE_T_H
#define __CVALUE_T_H

#include <stdint.h>
#include <cexceptions.h>

typedef enum value_t {
    VT_NONE,
    VT_INTMAX,
    VT_FLOAT,
    VT_STRING,
    VT_ENUM,
    VT_NULL,
} value_t;

typedef struct const_value_t {
    union {
        double f;
        intmax_t i;
        char *s;
    } value;
    value_t value_type;
} const_value_t;

void const_value_free( const_value_t *x );

char *const_value_string( const_value_t *val );

long const_value_integer( const_value_t *val );

double const_value_real( const_value_t *val );

void const_value_move( const_value_t *dst, const_value_t *src );

void const_value_copy( const_value_t *dst, const_value_t *src,
		       cexception_t *ex );

value_t const_value_type( const_value_t *v );

const_value_t make_zero_const_value();

const_value_t make_const_value( cexception_t *ex,
				value_t value_type, ... );

void const_value_to_float( const_value_t *x );
void const_value_to_string( const_value_t *x, cexception_t *ex );
void const_value_to_int( const_value_t *x );

const_value_t const_value_strcat( const_value_t *s1, const_value_t *s2,
				  cexception_t *ex );

const_value_t const_value_add( const_value_t x, const_value_t y );
const_value_t const_value_sub( const_value_t x, const_value_t y );
const_value_t const_value_mul( const_value_t x, const_value_t y );
const_value_t const_value_div( const_value_t x, const_value_t y );
const_value_t const_value_mod( const_value_t x, const_value_t y );

const_value_t const_value_negate( const_value_t x );

const char *cvalue_type_name( const_value_t val );

#endif
