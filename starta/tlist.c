/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <tlist.h>

/* uses: */
#include <sllist.h>

void delete_tlist( TLIST *list )
{
    delete_sllist( (SLLIST*)list );
}

TLIST* new_tlist( TNODE *tnode,
                  TLIST *next,
                  cexception_t *ex )
{
    return (TLIST*)new_sllist( tnode, (break_cycle_function_t) tnode_break_cycles,
                               (delete_function_t) delete_tnode,
                               (SLLIST*) next, ex );
}

void create_tlist( TLIST * volatile *list,
                   TNODE * volatile *data,
                   TLIST *next, cexception_t *ex )
{
    create_sllist( (SLLIST * volatile *)list,
		   (void * volatile *)data,
                   (break_cycle_function_t) tnode_break_cycles,
		   (dispose_function_t) dispose_tnode,
		   (SLLIST*) next, ex );
}

TLIST* clone_tlist( TLIST *tlist, cexception_t *ex )
{
    TLIST *volatile clone = NULL;
    TLIST *volatile next = NULL;
    TNODE *volatile tnode = share_tnode( tlist_data( tlist ));
    cexception_t inner;

    cexception_guard( inner ) {
        if( tlist != NULL ) {
            next = clone_tlist( tlist_next( tlist ), &inner );
            clone = new_tlist( /*tnode =*/ NULL, next, &inner );
            next = NULL;
            tlist_set_data( clone, &tnode );
        }
    }
    cexception_catch {
        delete_tlist( clone );
        delete_tlist( next );
        delete_tnode( tnode );
        cexception_reraise( inner, ex );
    }

    return clone;
}

void tlist_traverse_tnodes_and_set_rcount2( TLIST *tlist )
{
    SLLIST *current = (SLLIST*)tlist;

    for( ; current != NULL; current = sllist_next(current) ) {
	if( sllist_data(current) ) {
            tnode_traverse_rcount2( (TNODE*)sllist_data(current) );
        }
    }
}

void tlist_traverse_tnodes_and_mark_accessible( TLIST *tlist )
{
    SLLIST *current = (SLLIST*)tlist;

    for( ; current != NULL; current = sllist_next(current) ) {
	if( sllist_data(current) ) {
            tnode_mark_accessible( (TNODE*)sllist_data(current) );
        }
    }
}

void tlist_break_cycles( TLIST *list )
{
    sllist_break_cycles( (SLLIST *)list );
}

void dispose_tlist( TLIST* volatile *list )
{
    dispose_sllist( (SLLIST* volatile *)list );
}

TNODE* tlist_data( TLIST *list )
{
    return (TNODE*) sllist_data( (SLLIST *)list );
}

TNODE* tlist_extract_data( TLIST *list )
{
    return (TNODE*) sllist_extract_data( (SLLIST *)list );
}

void tlist_set_data( TLIST *list, TNODE * volatile *code )
{
    sllist_set_data( (SLLIST *)list, (void * volatile*)code );
}

TLIST* tlist_next( TLIST *list )
{
    return (TLIST*) sllist_next( (SLLIST *)list );
}

void tlist_disconnect( TLIST *list )
{
    sllist_disconnect( (SLLIST *)list );
}

void tlist_push( TLIST *volatile *list,
		   TLIST *volatile *node,
		   cexception_t *ex )
{
    sllist_push( (SLLIST *volatile *)list,
		 (SLLIST *volatile *)node,
		 ex );
}

void tlist_push_data( TLIST *volatile *list,
			TNODE *volatile *data,
			tnode_delete_function_t delete_fn,
			tnode_dispose_function_t dispose_fn,
			cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
                      (break_cycle_function_t) tnode_break_cycles,
		      (delete_function_t) delete_fn,
		      (dispose_function_t) dispose_fn,
		      ex );
}

void tlist_push_tnode( TLIST *volatile *list,
		      TNODE *volatile *data,
		      cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
                      (break_cycle_function_t) tnode_break_cycles,
		      (delete_function_t) delete_tnode,
		      NULL,
		      ex );
}

TLIST* tlist_pop( TLIST * volatile *list )
{
    return (TLIST*) sllist_pop( (SLLIST * volatile *)list );
}

TNODE* tlist_pop_data( TLIST * volatile *list )
{
    return (TNODE*) sllist_pop_data( (SLLIST * volatile *)list );
}

void tlist_drop( TLIST * volatile *list )
{
    sllist_drop( (SLLIST * volatile *)list );
}

void tlist_swap( TLIST * volatile *list )
{
    sllist_swap( (SLLIST * volatile *)list );
}
