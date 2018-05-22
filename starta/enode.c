/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* Representation of the expression parse tree -- enodes (expression nodes) */
/* Enode tree is generated by the parser (*.y) and possibly
   simplified by the machine-independent optimiser */
/* From the enode tree machine code will be generated. */

/* exports: */
#include <enode.h>

/* uses: */
#include <tnode.h>
#include <cexceptions.h>
#include <allocx.h>
#include <assert.h>

#include <stdio.h>

struct ENODE {
    enode_flag_t flags;

    union {
	TNODE *expr_type;     /* type of the expression, given as a
				 reference to type symbol table node
				 (tnode) */
	DNODE *variable;      /* reference to the variable if
				 EF_VARADDR_EXPR is set*/
    } value;

    int rcount;           /* reference counter */
    ENODE *next;  /* links enodes into a linked list */
};

#include <enode_a.ci>

void dispose_enode( ENODE *volatile *node )
{
    assert( node );
    delete_enode( *node );
    *node = NULL;
}

void delete_enode( ENODE* node )
{
    if( node ) {
	if( node->rcount <= 0 ) {
	    printf( "!!! enode->rcound == %d !!!\n", node->rcount );
	    assert( node->rcount > 0 );
	}
        if( --node->rcount > 0 )
	    return;
	if( node->next ) delete_enode( node->next );
	if( node->flags & EF_VARADDR_EXPR ) {
	    if( node->value.variable ) delete_dnode( node->value.variable );
	} else {
	    if( node->value.expr_type ) delete_tnode( node->value.expr_type );
	}
        free_enode( node );
    }
}

ENODE *enode_make_type_to_element_type( ENODE *enode )
{
    assert( enode );
    if( enode->value.expr_type )
        enode->value.expr_type =
            tnode_convert_to_element_type( enode->value.expr_type );
    return enode;
}

ENODE *enode_make_type_to_addressof( ENODE *enode, cexception_t *ex )
{
    assert( enode );
    enode->value.expr_type = new_tnode_addressof( enode->value.expr_type, ex );
    return enode;
}

ENODE *enode_replace_type( ENODE *enode, TNODE *replacement )
{
    assert( enode );
    delete_tnode( enode->value.expr_type );
    enode->value.expr_type = replacement;
    return enode;
}

TNODE *enode_type( ENODE *enode )
{
    assert( enode );
    if( !(enode->flags & EF_VARADDR_EXPR) ) {
	return enode->value.expr_type;
    } else {
	return NULL;
    }
}

DNODE *enode_variable( ENODE *enode )
{
    assert( enode );
    if( enode->flags & EF_VARADDR_EXPR ) {
	return enode->value.variable;
    } else {
	return NULL;
    }
}

ENODE *enode_next( ENODE *enode )
{
    assert( enode );
    return enode->next;
}

int enode_size( ENODE *enode )
{
    assert( enode );
    if( enode->value.expr_type ) {
	return tnode_size( enode->value.expr_type );
    } else {
	return 0;
    }
}

ENODE *enode_set_flags( ENODE *enode, enode_flag_t flags )
{
    enode->flags |= flags;
    return enode;
}

ENODE *enode_reset_flags( ENODE *enode, enode_flag_t flags )
{
    enode->flags &= ~flags;
    return enode;
}

int enode_has_flags( ENODE *enode, enode_flag_t flags )
{
    return (enode->flags & flags);
}

ENODE *enode_set_has_errors( ENODE *enode )
{
    assert( enode );
    enode->flags |= EF_HAS_ERRORS;
    return enode;
}

int enode_has_errors( ENODE *enode )
{
    assert( enode );
    return (enode->flags & EF_HAS_ERRORS);
}

enode_flag_t enode_flags( ENODE *enode )
{
    assert( enode );
    return enode->flags;
}

int enode_is_varaddr( ENODE *enode )
{
    if( enode ) {
	return (enode->flags & EF_VARADDR_EXPR) != 0;
    } else {
	return 0;
    }
}

int enode_is_guarding_retval( ENODE *enode )
{
    if( !enode ) return 0;

    return
	enode_has_flags( enode, EF_RETURN_VALUE ) &&	
	enode_has_flags( enode, EF_GUARDING_ARG );
}

int enode_is_reference( ENODE *expr )
{
    assert( expr );

    if( enode_has_flags( expr, EF_VARADDR_EXPR )) {
	if( !expr->value.variable ) {
	    return 0;
	} else {
	    TNODE *tnode = dnode_type( expr->value.variable );
	    return tnode && tnode_is_reference( tnode );
	}
    } else {
	if( !expr->value.expr_type ) {
	    return 0;
	} else {
	    return tnode_is_reference( expr->value.expr_type );
	}
    }
}

int enode_is_immutable( ENODE * expr )
{
    assert( expr );

    if( enode_has_flags( expr, EF_VARADDR_EXPR )) {
	if( !expr->value.variable ) {
	    return 0;
	} else {
	    TNODE *tnode = dnode_type( expr->value.variable );
	    return tnode && tnode_is_immutable( tnode );
	}
    } else {
	if( !expr->value.expr_type ) {
	    return 0;
	} else {
	    return tnode_is_immutable( expr->value.expr_type );
	}
    }
}

int enode_is_readonly_compatible_with_expr( ENODE *expr, ENODE *target )
{
    if( enode_has_flags( target, EF_IS_READONLY )) {
	return 0;
#if 0
    } else if( enode_is_reference( expr ) && !enode_is_immutable( expr ) &&
	       enode_has_flags( expr, EF_IS_READONLY )) {
	return 0;
#endif
    } else {
	return 1;
    }
}

int enode_is_readonly_compatible_with_var( ENODE *expr, DNODE *variable )
{
    if( dnode_has_flags( variable, DF_IS_READONLY )) {
	return 0;
#if 0
    }
    else if( enode_is_reference( expr ) && !enode_is_immutable( expr ) &&
	       enode_has_flags( expr, EF_IS_READONLY )) {
	return 0;
#endif
    } else {
	return 1;
    }
}

int enode_is_readonly_compatible_for_init( ENODE *expr, DNODE *variable )
{
#if 0
    if( dnode_has_flags( variable, DF_IS_READONLY )) {
	return 1;
    } else if( enode_is_reference( expr ) && !enode_is_immutable( expr ) &&
	       enode_has_flags( expr, EF_IS_READONLY )) {
	return 0;
    } else {
	return 1;
    }
#else
    return 1;
#endif
}

int enode_is_readonly_compatible_for_param( ENODE *expr, DNODE *variable )
{
    if( dnode_has_flags( variable, DF_IS_READONLY )) {
	return 1;
    } else if( enode_is_reference( expr ) && !enode_is_immutable( expr ) &&
	       enode_has_flags( expr, EF_IS_READONLY )) {
	return 0;
    } else {
	return 1;
    }
}

ENODE* enode_append( ENODE *head, ENODE *tail )
{
    ENODE *last;
    if( !head ) {
        return tail;
    } else {
        last = head;
        while( last->next ) {
	    last = last->next;
	}
	last->next = tail;
	return head;
    }
}

ENODE *share_enode( ENODE *enode )
{
    if( enode )
	enode->rcount++;
    return enode;
}

ENODE *new_enode( cexception_t *ex )
{
    ENODE *enode = alloc_enode( ex );
    enode->rcount = 1;
    return enode;
}

ENODE *new_enode_typed( TNODE *volatile *tnode, cexception_t *ex )
{
    ENODE *enode = new_enode( ex );
    assert( tnode );
    enode->value.expr_type = *tnode;
    *tnode = NULL;
    return enode;
}

ENODE *new_enode_return_value( TNODE *retval_tnode, cexception_t *ex )
{
    ENODE *enode = new_enode( ex );
    enode_set_flags( enode, EF_RETURN_VALUE );
    enode->value.expr_type = retval_tnode;
    return enode;
}

ENODE *new_enode_guarding_arg( cexception_t *ex )
{
    ENODE *enode = new_enode( ex );
    enode_set_flags( enode, EF_GUARDING_ARG );
    return enode;
}

ENODE *new_enode_varaddr_expr( DNODE *var_dnode, cexception_t *ex )
{
    ENODE *enode = new_enode( ex );
    enode_set_flags( enode, EF_VARADDR_EXPR );
    enode->value.variable = var_dnode;
    if( dnode_has_flags( var_dnode, DF_IS_READONLY )) {
	enode_set_flags( enode, EF_IS_READONLY );
    }
    return enode;
}

void enode_append_element_type( ENODE *enode, TNODE *element_type )
{
    assert( enode );
    if( !enode->value.expr_type ) {
	enode->value.expr_type = element_type;
    } else {
	enode->value.expr_type =
	    tnode_append_element_type( enode->value.expr_type, element_type );
    }
}

void enode_list_push( ENODE **ptr_list, ENODE *enode )
{
    ENODE *list;

    assert( ptr_list );
    list = *ptr_list;

    if( !list ) {
	*ptr_list = enode;
    } else
    if( enode ) {
	*ptr_list = enode_append( enode, list );
    }
}

static ENODE *enode_disconnect( ENODE *enode )
{
    if( enode ) {
	enode->next =  NULL;
    }
    return enode;
}

ENODE *enode_list_pop( ENODE **ptr_list )
{
    ENODE *ret_node;
    ENODE *list;

    assert( ptr_list );
    list = *ptr_list;

    if( !list ) {
	return NULL;
    } else {
	ret_node = list;
	list = enode_next( list );
	enode_disconnect( ret_node );
	*ptr_list = list;
	return ret_node;
    }
}

void enode_list_drop( ENODE **ptr_list )
{
    ENODE *dropped_enode;

    assert( ptr_list );
    dropped_enode = *ptr_list;

    if( dropped_enode ) {
	*ptr_list = enode_next( dropped_enode );
	enode_disconnect( dropped_enode );
	delete_enode( dropped_enode );
    }
}

void enode_list_swap( ENODE **list )
{
    ENODE *top1, *top2;

    assert( list );

    top1 = enode_list_pop( list );
    top2 = enode_list_pop( list );
    enode_list_push( list, top1 );
    enode_list_push( list, top2 );
}
