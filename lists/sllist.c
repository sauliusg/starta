/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <sllist.h>

/* uses: */
#include <stdio.h>
#include <stdlib.h>
#include <allocx.h>
#include <assert.h>

struct SLLIST {
    ssize_t rcount;
    void *data;
    delete_function_t delete_fn;
    dispose_function_t dispose_fn;
    SLLIST *next;
};

void delete_sllist( SLLIST *list )
{
    SLLIST *next;

    while( list ) {
	if( list->rcount <= 0 ) {
	    printf( "!!! sllist->rcound == %d !!!\n", list->rcount );
	    assert( list->rcount > 0 );
	}
        if( --list->rcount > 0 )
	    return;
	next = list->next;
	if( list->data ) {
	    if( list->delete_fn ) {
		(*list->delete_fn)( list->data );
	    } else if( list->dispose_fn ) {
		(*list->dispose_fn)( &list->data );
	    }
	}
	freex( list );
	list = next;
    }
}

SLLIST* new_sllist( void *data,
		    delete_function_t delete_fn,
		    SLLIST *next,
		    cexception_t *ex )
{
    SLLIST *list = callocx( sizeof(*list), 1, ex );

    list->rcount = 1;
    list->data = data;
    list->delete_fn = delete_fn;
    list->next = next;

    return list;
}

SLLIST *share_sllist( SLLIST *list )
{
    if( list ) {
	list->rcount ++;
    }
    return list;
}

void create_sllist( SLLIST * volatile *list,
		    void * volatile *data,
		    dispose_function_t dispose_fn,
		    SLLIST *next, cexception_t *ex )
{
    SLLIST *node;

    assert( list );
    assert( !*list );

    node = new_sllist( /*data*/ NULL, /*delete_fn*/ NULL, next, ex );
    if( data ) {
	node->data = *data;
	*data = NULL;
    }
    node->dispose_fn = dispose_fn;

    *list = node;
}
		    
void dispose_sllist( SLLIST* volatile *list )
{
    if( list && *list ) {
	delete_sllist( *list );
	*list = NULL;
    }
}

void* sllist_data( SLLIST *list )
{
    if( list ) {
	return list->data;
    } else {
	return NULL;
    }
}

void* sllist_extract_data( SLLIST *list )
{
    if( list ) {
	void *returned_data = list->data;
	list->data = NULL;
	return returned_data;
    } else {
	return NULL;
    }
}

void sllist_set_data( SLLIST *list, void * volatile *data )
{
    assert( list );
    assert( data );
    assert( !list->data );

    list->data = *data;
    *data = NULL;
}

SLLIST* sllist_next( SLLIST *list )
{
    if( list ) {
	return list->next;
    } else {
	return NULL;
    }
}

void sllist_disconnect( SLLIST *list )
{
    if( list ) {
	list->next = NULL;
    }
}

void sllist_push( SLLIST *volatile *list,
		  SLLIST *volatile *node,
		  cexception_t *ex )
{
    assert( list );
    assert( node );
    assert( !(*node) || (*node)->next == NULL );

    if( *node ) {
	(*node)->next = *list;
	*list = *node;
	*node = NULL;
    }
}

void sllist_push_data( SLLIST *volatile *list,
		       void *volatile *data,
		       delete_function_t delete_fn,
		       dispose_function_t dispose_fn,
		       cexception_t *ex )
{
    SLLIST *node = NULL;

    assert( list );
    assert( data );

    node = new_sllist( *data, delete_fn, *list, ex );
    node->dispose_fn = dispose_fn;

    *data = NULL;
    *list = node;
}

void sllist_push_shared_data( SLLIST *volatile *list,
			      void *data,
			      delete_function_t delete_fn,
			      dispose_function_t dispose_fn,
			      share_function_t share_fn,
			      cexception_t *ex )
{
    SLLIST *node = NULL;

    assert( list );

    node = new_sllist( NULL, delete_fn, *list, ex );

    if( share_fn && data ) {
	node->data = (*share_fn)( data );
    } else {
	node->data = data;
    }

    node->dispose_fn = dispose_fn;

    *list = node;
}

SLLIST* sllist_pop( SLLIST * volatile *list )
{
    SLLIST *top = NULL;

    assert( list );

    top = *list;
    if( top ) {
	*list = top->next;
	top->next = NULL;
    }

    return top;
}

void* sllist_pop_data( SLLIST * volatile *list )
{
    SLLIST *top = NULL;
    void *data = NULL;

    assert( list );

    top = sllist_pop( list );

    if( top && top->data ) {
	data = top->data;
	top->data = NULL;
    }

    delete_sllist( top );

    return data;
}

void sllist_drop( SLLIST * volatile *list )
{
    SLLIST *top = NULL;

    assert( list );

    top = sllist_pop( list );

    delete_sllist( top );
}

void sllist_swap( SLLIST * volatile *list )
{
    SLLIST *top = NULL;
    SLLIST *next = NULL;

    assert( list );

    if( *list && (*list)->next ) {
	top = *list;
	next = top->next;
	top->next = next->next;
	next->next = top;
	*list = next;
    }
}
