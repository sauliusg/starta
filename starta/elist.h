/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __ELIST_H
#define __ELIST_H

#include <enode.h>

typedef struct ELIST ELIST;

typedef void (*enode_delete_function_t)( ENODE* );
typedef void (*enode_dispose_function_t)( ENODE* volatile * );

void delete_elist( ELIST *list );
ELIST* new_elist( ENODE *enode,
		      enode_delete_function_t delete_fn,
		      ELIST *next,
		      cexception_t *ex );
void create_elist( ELIST * volatile *list,
		     ENODE * volatile *data,
		     enode_dispose_function_t dispose_fn,
		     ELIST *next, cexception_t *ex );
void dispose_elist( ELIST* volatile *list );
ENODE* elist_data( ELIST *list );
ENODE* elist_extract_data( ELIST *list );
void elist_set_data( ELIST *list, ENODE * volatile *code );
ELIST* elist_next( ELIST *list );
void elist_disconnect( ELIST *list );
void elist_push( ELIST *volatile *list,
		   ELIST *volatile *node,
		   cexception_t *ex );
void elist_push_data( ELIST *volatile *list,
			ENODE *volatile *data,
			enode_delete_function_t delete_fn,
			enode_dispose_function_t dispose_fn,
			cexception_t *ex );
ELIST* elist_pop( ELIST * volatile *list );
ENODE* elist_pop_data( ELIST * volatile *list );
void elist_drop( ELIST * volatile *list );
void elist_swap( ELIST * volatile *list );

#endif
