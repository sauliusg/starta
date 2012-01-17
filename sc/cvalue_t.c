/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* This file implements compile-time constant arithmetic (a kind of
   specialised compile time constant folding) */

/* exports: */
#include <cvalue_t.h>

/* uses: */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>
#include <yy.h>
#include <cexceptions.h>
#include <stringx.h>
#include <allocx.h>
#include <assert.h>

void const_value_free( const_value_t *x )
{
    assert( x );
    if( x->value_type == VT_STRING ) {
	freex( x->value.s );
	x->value.s = NULL;
	x->value_type = VT_NONE;
    }
}

char *const_value_string( const_value_t *val )
{
    assert( val );
    assert( val->value_type == VT_STRING || val->value_type == VT_ENUM );
    return val->value.s;
}

long const_value_integer( const_value_t *val )
{
    assert( val );
    assert( val->value_type == VT_INT );
    return val->value.i;
}

double const_value_real( const_value_t *val )
{
    assert( val );
    assert( val->value_type == VT_FLOAT );
    return val->value.f;
}

void const_value_move( const_value_t *dst, const_value_t *src )
{
    assert( dst );
    assert( src );
    if( src != dst ) {
	const_value_free( dst );
	*dst = *src;
	memset( src, 0, sizeof(*src) );
    }
}

void const_value_copy( const_value_t *dst, const_value_t *src,
		       cexception_t *ex )
{
    assert( dst );
    assert( src );
    if( src != dst ) {
	const_value_free( dst );
	if( src->value_type == VT_STRING ) {
	    dst->value.s = strdupx( src->value.s, ex );
	} else {
	    dst->value = src->value;
	}
	dst->value_type = src->value_type;
    }
}

value_t const_value_type( const_value_t *v )
{
    assert( v );
    return v->value_type;
}

const_value_t make_zero_const_value()
{
    const_value_t r;
    memset( &r, 0, sizeof( r ));
    r.value_type = VT_INT;
    return r;
}

const_value_t make_const_value( cexception_t *ex,
				value_t value_type, ... )
{
    const_value_t r = make_zero_const_value();
    va_list v;

    va_start( v, value_type );

    r.value_type = value_type;

    switch( value_type ) {
    case VT_INT:
	r.value.i = va_arg( v, int );
	break;
    case VT_FLOAT:
	r.value.f = va_arg( v, double );
	r.value_type = VT_FLOAT;
	break;
    case VT_STRING:
	r.value.s = strdupx( va_arg( v, char* ), ex );
	r.value_type = VT_STRING;
	break;
    case VT_ENUM: {
	char *value_name = va_arg( v, char* );
	char *type_name = va_arg( v, char* );
	ssize_t length = strlen( value_name ) + strlen( type_name ) + 2;

	r.value.s = callocx( length, 1, ex );
	strcpy( r.value.s, value_name );
	strcat( r.value.s, " " );
	strcat( r.value.s, type_name );
	break;
	}
    case VT_NULL:
	r.value.s = NULL;
	break;
    default:
	assert(0);
    }

    va_end( v );

    return r;
}

void const_value_to_float( const_value_t *x )
{
    double d;
    switch( x->value_type ) {
        case VT_INT:
	    x->value.f = x->value.i;
	    break;
        case VT_FLOAT:
	    break;
        case VT_STRING:
	    d = atof( x->value.s );
	    const_value_free( x );
	    x->value.f = d;
	    break;
        case VT_ENUM:
	    yyerrorf( "can not use enum value in constant expression" );
	    break;
        default:
	    assert(0);
    }
    x->value_type = VT_FLOAT;
}

void const_value_to_string( const_value_t *x, cexception_t *ex )
{
    char buff[80];
    switch( x->value_type ) {
        case VT_INT:
	    snprintf( buff, sizeof(buff)-1, "%jd", x->value.i );
	    break;
        case VT_FLOAT:
	    snprintf( buff, sizeof(buff)-1, "%lg", x->value.f );
	    break;
        case VT_STRING:
	    return;
	    break;
        case VT_ENUM:
	    return;
	    break;
        default:
	    assert(0);
    }
    x->value.s = strdupx( buff, ex );
    x->value_type = VT_STRING;
}

void const_value_to_int( const_value_t *x )
{
    long l;
    switch( x->value_type ) {
        case VT_INT:
	    break;
        case VT_FLOAT:
	    x->value.i = /* ceill( x->value.f - 0.5 ); */ (int)( x->value.f - 0.5 );
	    break;
        case VT_STRING:
	    l = atol( x->value.s );
	    const_value_free( x );
	    x->value.i = l;
	    break;
        case VT_ENUM:
	    yyerrorf( "can not use enum value in constant expression" );
	    break;
        default:
	    assert(0);
    }
    x->value_type = VT_INT;
}

const_value_t const_value_strcat( const_value_t *s1, const_value_t *s2,
				  cexception_t *ex )
{
    const_value_t s = make_zero_const_value();

    const_value_to_string( s1, ex );
    const_value_to_string( s2, ex );

    s.value.s = mallocx( strlen(s1->value.s) + strlen(s2->value.s) + 1, ex );

    strcpy( s.value.s, s1->value.s );
    strcat( s.value.s, s2->value.s );

    const_value_free( s1 );
    const_value_free( s2 );

    s.value_type = VT_STRING;

    return s;
}

static const_value_t const_value_arithm( const_value_t *x, const_value_t *y,
					 long (*larithm)(long,long),
					 double (*farithm)(double,double) )
{
    const_value_t r = make_zero_const_value();

    if( x->value_type == VT_INT && y->value_type == VT_INT ) {
	assert( larithm );
	r.value.i = larithm( x->value.i, y->value.i );
	r.value_type = VT_INT;
    } else if( x->value_type == VT_FLOAT || y->value_type == VT_FLOAT ) {
	const_value_to_float( x );
	const_value_to_float( y );
	assert( farithm );
	r.value.f = farithm( x->value.f, y->value.f );
	r.value_type = VT_FLOAT;
    } else if( x->value_type == VT_INT || y->value_type == VT_INT ) {
	const_value_to_int( x );
	const_value_to_int( y );
	assert( larithm );
	r.value.i = larithm( x->value.i, y->value.i );
	r.value_type = VT_INT;
    } else {
	assert( 0 );
    }
    
    return r;
}

static long ladd( long x, long y ) { return x + y; }
static double fadd( double x, double y ) { return x + y; }

const_value_t const_value_add( const_value_t x, const_value_t y )
{
    return const_value_arithm( &x, &y, ladd, fadd );
}

static long lsub( long x, long y ) { return x - y; }
static double fsub( double x, double y ) { return x - y; }

const_value_t const_value_sub( const_value_t x, const_value_t y )
{
    return const_value_arithm( &x, &y, lsub, fsub );
}

static long lmul( long x, long y ) { return x * y; }
static double fmul( double x, double y ) { return x * y; }

const_value_t const_value_mul( const_value_t x, const_value_t y )
{
    return const_value_arithm( &x, &y, lmul, fmul );
}

static long _ldiv( long x, long y ) { return x / y; }
static double _fdiv( double x, double y ) { return x / y; }

const_value_t const_value_div( const_value_t x, const_value_t y )
{
    return const_value_arithm( &x, &y, _ldiv, _fdiv );
}

static long lmod( long x, long y ) { return x % y; }

const_value_t const_value_mod( const_value_t x, const_value_t y )
{
    return const_value_arithm( &x, &y, lmod, NULL );
}

const_value_t const_value_negate( const_value_t x )
{
    if( x.value_type == VT_INT ) {
	x.value.i = -x.value.i;
    } else if( x.value_type == VT_FLOAT ) {
	x.value.f = -x.value.f;
    } else {
	return x;
    }
    
    return x;    
}

const char *cvalue_type_name( const_value_t val )
{
    switch( val.value_type ) {
    case VT_INT: return "integer";
    case VT_FLOAT: return "float";
    case VT_STRING: return "string";
    case VT_ENUM: return "enumerator";
    case VT_NULL: return "null constant";
    default: return "unknown type";
    }
}
