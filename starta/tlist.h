/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TLIST_H
#define __TLIST_H

typedef struct TLIST TLIST;

#include <tnode.h>
#include <cexceptions.h>

typedef void (*tnode_delete_function_t)( TNODE* );
typedef void (*tnode_dispose_function_t)( TNODE* volatile * );

void delete_tlist( TLIST *list );
TLIST* new_tlist( TNODE *tnode,
                  TLIST *next,
                  cexception_t *ex );
void create_tlist( TLIST * volatile *list,
                   TNODE * volatile *data,
                   TLIST *next, cexception_t *ex );
TLIST* clone_tlist( TLIST *tlist, cexception_t *ex );
void tlist_traverse_tnodes_and_set_rcount2( TLIST *tlist );
void tlist_traverse_tnodes_and_mark_accessible( TLIST *tlist );
void tlist_break_cycles( TLIST *list );
void dispose_tlist( TLIST* volatile *list );
TNODE* tlist_data( TLIST *list );
TNODE* tlist_extract_data( TLIST *list );
void tlist_set_data( TLIST *list, TNODE * volatile *code );
TLIST* tlist_next( TLIST *list );
void tlist_disconnect( TLIST *list );
void tlist_push( TLIST *volatile *list,
                 TLIST *volatile *node,
                 cexception_t *ex );
void tlist_push_data( TLIST *volatile *list,
                      TNODE *volatile *data,
                      tnode_delete_function_t delete_fn,
                      tnode_dispose_function_t dispose_fn,
                      cexception_t *ex );
void tlist_push_tnode( TLIST *volatile *list,
		       TNODE *volatile *data,
		       cexception_t *ex );
TLIST* tlist_pop( TLIST * volatile *list );
TNODE* tlist_pop_data( TLIST * volatile *list );
void tlist_drop( TLIST * volatile *list );
void tlist_swap( TLIST * volatile *list );

#define foreach_tlist( NODE, LIST ) \
   for( NODE = LIST; NODE != NULL; NODE = tlist_next( NODE ))

#endif
