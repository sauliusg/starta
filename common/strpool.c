/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <strpool.h>

/* uses: */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <allocx.h>
#include <stringx.h>
#include <cexceptions.h>
#include <assert.h>

#define INITIAL_POOL_LENGTH 4

typedef union {
    int next;
    char *str;
} strpool_t;

typedef struct STRPOOL {
    ssize_t pool_length;
    strpool_t *pool;
    int next_free;
} STRPOOL;


STRPOOL *new_strpool( cexception_t *ex )
{
    STRPOOL *p = callocx( 1, sizeof(*p), ex );
    p->next_free = -1;
    return p;
}

void free_strpool( STRPOOL *p )
{
    ssize_t i;

    i = p->next_free;
    while( i >= 0 ) {
        p->next_free = p->pool[i].next;
        p->pool[i].str = NULL;
        i = p->next_free;
    }
    for( i = 0; i < p->pool_length; i++ ) {
        if( p->pool[i].str != NULL ) {
            free( p->pool[i].str );
        }
    }
    free( p->pool );
    p->pool = NULL;
    p->pool_length = 0;
    p->next_free = -1;
}

void delete_strpool( STRPOOL *pool )
{
    if( pool ) {
        free_strpool( pool );
        freex( pool );
    }
}

void dispose_strpool( STRPOOL *volatile *pool )
{
    if( pool ) {
        delete_strpool( *pool );
        *pool = NULL;
    }
}

static void realloc_strpool( STRPOOL *p, cexception_t *ex )
{
    ssize_t new_pool_length =
        p->pool_length == 0 ? INITIAL_POOL_LENGTH : p->pool_length * 2;

    p->pool = reallocx( p->pool, new_pool_length * sizeof(p->pool[0]), ex );
    p->next_free = p->pool_length;
    ssize_t i;
    for( i = p->pool_length; i < new_pool_length - 1; i++ ) {
        p->pool[i].next = i+1;
    }
    p->pool[new_pool_length - 1].next = -1;
    p->pool_length = new_pool_length;
}

ssize_t strpool_insert_string( STRPOOL *p, char *volatile *str, cexception_t *ex )
{
    assert(p);
    assert(str);

    if( p->next_free < 0 ) {
        realloc_strpool( p, ex );
    }

    assert( p->next_free >= 0 );

    ssize_t index = p->next_free;
    p->next_free = p->pool[index].next;
    p->pool[index].str = *str;
    *str = NULL;
    return index;
}

ssize_t strpool_add_string( STRPOOL *p, char *str, cexception_t *ex )
{
    char *dup = strdupx( str, ex );
    return strpool_insert_string( p, &dup, ex );
}

ssize_t strpool_strclone( STRPOOL *p, char *str )
{
    int volatile idx;
    cexception_t inner;
    cexception_guard( inner ) {
        idx = strpool_add_string( p, str, &inner );
    }
    cexception_catch {
        return -1;
    }
    return idx;
}

ssize_t strpool_strnclone( STRPOOL *p, char *str, size_t length )
{
    int volatile idx;
    char *volatile cloned;
    cexception_t inner;
    cexception_guard( inner ) {
        cloned = mallocx( length + 1, &inner );
        strncpy( cloned, str, length );
        cloned[length] = '\0';
        idx = strpool_insert_string( p, &cloned, &inner );
    }
    cexception_catch {
        freex( cloned );
        return -1;
    }
    return idx;
}

char *obtain_string_from_strpool( STRPOOL *p, ssize_t index )
{
    char *string;
    if( index < 0 ) {
        return NULL;
    } else {
        string = p->pool[index].str;
        p->pool[index].next = p->next_free;
        p->next_free = index;
        return string;
    }
}

char *strpool_get_string( STRPOOL *p, ssize_t index )
{
    if( index < 0 ) {
        return NULL;
    } else {
        return p->pool[index].str;
    }
}

static int is_free( STRPOOL *p, int i )
{
    int j = p->next_free;
    while( j >= 0 ) {
        if( i == j ) {
            return 1;
        }
        j = p->pool[j].next;
    }
    return 0;
}

void strpool_print_strings( STRPOOL *p )
{
    for( int i = 0; i < p->pool_length; i++ ) {
        if( !is_free( p, i )) {
            printf( "%d: \"%s\"\n", i, p->pool[i].str );
        }
    }
}
