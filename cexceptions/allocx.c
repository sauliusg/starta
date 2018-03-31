/*---------------------------------------------------------------------------*\
** $Author$
** $Date$ 
** $Revision$
** $URL$
\*---------------------------------------------------------------------------*/

/* memory allocation functions that use cexception handling */

#include <stdlib.h>
#include <allocx.h>

void *allocx_subsystem = &allocx_subsystem;

#define merror( EX ) cexception_raise_in( EX, allocx_subsystem, \
					  ALLOCX_NO_MEMORY,     \
					  "Not enough memory" )

long long alloc_count;

void *mallocx( size_t size, cexception_t *ex )
{
    void *p;
    if( size != 0 ) {
        p = malloc( size + sizeof(alloc_count) );
	if( !p ) merror( ex );
    } else {
        p = NULL;
    }
    if( p ) {
        *((long long*)p) = ++alloc_count;
        if( alloc_count == 7 ) {
            printf( ".... allocating node no. %zd\n", alloc_count );
        }
        printf( ">>> malloc node no. %Ld %p\n", *(long long*)p, p );
        p = (void*) ( (long long*)p + 1 );
    }
    return p;
}

void *callocx( size_t size, size_t nr, cexception_t *ex )
{
    void *p;
    if( size != 0 && nr != 0 ) {
        p = calloc( size, nr + sizeof(long long)/size + 1 );
	if( !p ) merror( ex );
    } else {
        p = NULL;
    }
    if( p ) {
        *((long long*)p) = ++alloc_count;
        if( alloc_count == 7 ) {
            printf( ".... allocating node no. %zd\n", alloc_count );            
        }
        printf( ">>> calloc node no. %Ld %p\n", *(long long*)p, p );
        p = (void*) ( (long long*)p + 1 );
    }
    return p;
}

void *reallocx( void *buffer, size_t new_size, cexception_t *ex )
{
    void *p;
    if( buffer )
        buffer = (void*) ( (long long*)buffer - 1 );
    if( new_size != 0 ) {
        p = realloc( buffer, new_size  + sizeof(alloc_count) );
	if( !p ) merror( ex );
    } else {
        p = buffer;
    }
    if( p ) {
        if( !buffer )
            *((long long*)p) = ++alloc_count;
        if( alloc_count == 7 ) {
            printf( ".... allocating node no. %zd\n", alloc_count );
        }
        printf( ">>> reallocating node no. %Ld %p\n", *(long long*)p, p );
        p = (void*) ( (long long*)p + 1 );
    }
    return p;
}

void freex( void *p )
{
    if( p ) {
        p = (void*) ( (long long*)p - 1 );
        printf( ">>> freeing node no. %Ld\n", *(long long*)p );
        if( *(long long*)p > alloc_count ) {
            printf( "!!!! not my node, %p (%Ld)?!\n", p, *(long long*)p );
        }
        free( p );
    }
}

int checkptr( void *p )
{
    if( p ) {
        p = (void*) ( (long long*)p - 1 );
        if( *(long long*)p > alloc_count ) {
            printf( "<<<< not an alloc'ed node, %p (%Ld)?!\n", p, *(long long*)p );
        }
    }
}
