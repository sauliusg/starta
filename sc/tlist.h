/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TLIST_H
#define __TLIST_H

#include <tnode.h>

typedef struct TLIST TLIST;

typedef void (*tnode_delete_function_t)( TNODE* );
typedef void (*tnode_dispose_function_t)( TNODE* volatile * );

void delete_tlist( TLIST *list );
TLIST* new_tlist( TNODE *tnode,
		      tnode_delete_function_t delete_fn,
		      TLIST *next,
		      cexception_t *ex );
void create_tlist( TLIST * volatile *list,
		     TNODE * volatile *data,
		     tnode_dispose_function_t dispose_fn,
		     TLIST *next, cexception_t *ex );
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

#endif
