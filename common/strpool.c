/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <strpool.h>

/* uses: */
#include <stdlib.h>
#include <string.h>
#include <allocx.h>
#include <stringx.h>
#include <cexceptions.h>
#include <assert.h>

#define INITIAL_POOL_LENGTH 4

static ssize_t pool_length = 0;
static strpool_t *pool = NULL;
static int next_free = -1;

static void realloc_pool( cexception_t *ex )
{
    ssize_t new_pool_length =
        pool_length == 0 ? INITIAL_POOL_LENGTH : pool_length * 2;

    pool = reallocx( pool, new_pool_length * sizeof(pool[0]), ex );
    next_free = pool_length;
    ssize_t i;
    for( i = pool_length; i < new_pool_length - 1; i++ ) {
        pool[i].next = i+1;
    }
    pool[i].next = -1;
    pool_length = new_pool_length;
}

ssize_t pool_insert_string( char *volatile *str, cexception_t *ex )
{
    assert(str);

    if( next_free < 0 ) {
        realloc_pool( ex );
    }

    ssize_t index = next_free;
    next_free = pool[index].next;
    pool[index].str = *str;
    *str = NULL;
    return index;
}

ssize_t pool_add_string( char *str, cexception_t *ex )
{
    char *dup = strdupx( str, ex );
    return pool_insert_string( &dup, ex );
}

ssize_t pool_clone_string( char *str )
{
    int volatile idx;
    cexception_t inner;
    cexception_guard( inner ) {
        idx = pool_add_string( str, &inner );
    }
    cexception_catch {
        return -1;
    }
    return idx;
}

ssize_t pool_strnclone( char *str, size_t length )
{
    int volatile idx;
    char *volatile cloned;
    cexception_t inner;
    cexception_guard( inner ) {
        cloned = mallocx( length + 1, &inner );
        strncpy( cloned, str, length );
        cloned[length] = '\0';
        idx = pool_insert_string( &cloned, &inner );
    }
    cexception_catch {
        freex( cloned );
        return -1;
    }
    return idx;
}

char *obtain_string_from_pool( ssize_t index )
{
    char *string;
    if( index < 0 ) {
        return NULL;
    } else {
        string = pool[index].str;
        pool[index].next = next_free;
        next_free = index;
        return string;
    }
}

char *get_string_from_pool( ssize_t index )
{
    if( index < 0 ) {
        return NULL;
    } else {
        return pool[index].str;
    }
}

void free_pool()
{
    ssize_t i;

    i = next_free;
    while( i >= 0 ) {
        next_free = pool[i].next;
        pool[i].str = NULL;
        i = next_free;
    }
    for( i = 0; i < pool_length; i++ ) {
        if( pool[i].str != NULL ) {
            free( pool[i].str );
        }
    }
    pool_length = 0;
    free( pool );
    pool = NULL;
}
