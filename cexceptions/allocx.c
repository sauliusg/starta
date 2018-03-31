/*---------------------------------------------------------------------------*\
** $Author$
** $Date$ 
** $Revision$
** $URL$
\*---------------------------------------------------------------------------*/

/* memory allocation functions that use cexception handling */

#include <stdio.h>
#include <stdlib.h>
#include <allocx.h>

void *allocx_subsystem = &allocx_subsystem;

#define merror( EX ) cexception_raise_in( EX, allocx_subsystem, \
					  ALLOCX_NO_MEMORY,     \
					  "Not enough memory" )

#ifdef ALLOCX_DEBUG_COUNTS
long long alloc_count;
#endif

void *mallocx( size_t size, cexception_t *ex )
{
    void *p;
    if( size != 0 ) {
        p = malloc( size
#ifdef ALLOCX_DEBUG_COUNTS
                    + sizeof(alloc_count)
#endif
                    );
	if( !p ) merror( ex );
    } else {
        p = NULL;
    }
#ifdef ALLOCX_DEBUG_COUNTS
    if( p ) {
        *((long long*)p) = ++alloc_count;
#ifdef ALLOCX_DEBUG_PRINT
        printf( ">>>> malloc node %p (%Ld)\n", p, *(long long*)p );
#endif
        p = (void*) ( (long long*)p + 1 );
    }
#endif
    return p;
}

void *callocx( size_t size, size_t nr, cexception_t *ex )
{
    void *p;
    if( size != 0 && nr != 0 ) {
        p = calloc( size, nr
#ifdef ALLOCX_DEBUG_COUNTS
                    + sizeof(long long)/size + 1
#endif
                    );
	if( !p ) merror( ex );
    } else {
        p = NULL;
    }
#ifdef ALLOCX_DEBUG_COUNTS
    if( p ) {
        *((long long*)p) = ++alloc_count;
#ifdef ALLOCX_DEBUG_PRINT
        printf( ">>>> calloc node %p (%Ld)\n", p, *(long long*)p );
#endif
        p = (void*) ( (long long*)p + 1 );
    }
#endif
    return p;
}

void *reallocx( void *buffer, size_t new_size, cexception_t *ex )
{
    void *p;
#ifdef ALLOCX_DEBUG_COUNTS
    if( buffer )
        buffer = (void*) ( (long long*)buffer - 1 );
#endif
    if( new_size != 0 ) {
        p = realloc( buffer, new_size
#ifdef ALLOCX_DEBUG_COUNTS
                     + sizeof(alloc_count)
#endif
                     );
	if( !p ) merror( ex );
    } else {
        p = buffer;
    }
#ifdef ALLOCX_DEBUG_COUNTS
    if( p ) {
        if( !buffer )
            *((long long*)p) = ++alloc_count;
#ifdef ALLOCX_DEBUG_PRINT
        printf( ">>>> reallocating node %p (%Ld)\n", p, *(long long*)p );
#endif
        p = (void*) ( (long long*)p + 1 );
    }
#endif
    return p;
}

void freex( void *p )
{
    if( p ) {
#ifdef ALLOCX_DEBUG_COUNTS
        p = (void*) ( (long long*)p - 1 );
        if( *(long long*)p > alloc_count ) {
            printf( "!!!! not my node, %p (%Ld)?!\n", p, *(long long*)p );
        }
#ifdef ALLOCX_DEBUG_PRINT
        printf( "<<<< freeing node %p (%Ld)\n", p, *(long long*)p );
#endif
#endif
        free( p );
    }
}

#ifdef ALLOCX_DEBUG_COUNTS
int checkptr( void *p )
{
    if( p ) {
        p = (void*) ( (long long*)p - 1 );
        if( *(long long*)p > alloc_count ) {
            printf( "!!!!!! not an alloc'ed node, %p (%Ld)?!\n", p, *(long long*)p );
            return 0;
        } else {
            return 1;
        }
    }
    return 1;
}
#endif
