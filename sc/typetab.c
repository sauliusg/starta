/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <typetab.h>

/* uses: */
#include <string.h>
#include <tnode.h>
#include <cexceptions.h>
#include <allocx.h>
#include <stringx.h>
#include <assert.h>
#include <yy.h>

typedef struct TYPE_NODE {
    char *name;
    type_suffix_t suffix;
    TNODE *tnode;
    int scope;
    int subscope;
    struct TYPE_NODE *next;
} TYPE_NODE;

static TYPE_NODE *new_type_node_default( cexception_t *ex )
{
    return callocx( sizeof(TYPE_NODE), 1, ex );
}

static void delete_type_node( TYPE_NODE *node )
{
    if( node ) {
        freex( node->name );
	delete_tnode( node->tnode );
        freex( node );
    }
}

static void delete_type_node_list( TYPE_NODE *node )
{
    TYPE_NODE *next;
    while( node ) {
        next = node->next;
	delete_type_node( node );
	node = next;
    }
}

struct TYPETAB {
    TYPE_NODE *node;
    int current_scope;
    int current_subscope;
};

TYPETAB *new_typetab( cexception_t *ex )
{
    return callocx( sizeof(TYPETAB), 1, ex );
}

void delete_typetab( TYPETAB *table )
{
    if( !table ) return;
    delete_type_node_list( table->node );
    freex( table );
}

TNODE *typetab_insert( TYPETAB *table, const char *name,
		       TNODE *tnode, cexception_t *ex )
{
    return typetab_insert_suffix( table, name, TS_NOT_A_SUFFIX, tnode, ex );
}

TNODE *typetab_insert_suffix( TYPETAB *table, const char *name,
			      type_suffix_t suffix, TNODE *tnode,
			      cexception_t *ex )
{
    cexception_t inner;
    TYPE_NODE * volatile node = NULL;
    TNODE *ret = NULL;

    assert( table );
    assert( name );

    cexception_guard( inner ) {
        TNODE *lookup_node = typetab_lookup_suffix( table, name, suffix );
        if( lookup_node ) {
	    ret = lookup_node;
	} else {
	    node = new_type_node_default( ex );
	    node->tnode = tnode;
	    node->suffix = suffix;
	    node->scope = table->current_scope;
	    node->subscope = table->current_subscope;
	    node->name  = strdupx( (char*)name, &inner );
	    node->next  = table->node;
	    table->node = node;
	    ret = tnode;
	}
    }
    cexception_catch {
        delete_type_node( node );
	cexception_reraise( inner, ex );
    }
    return ret;
}

TNODE *typetab_override_suffix( TYPETAB *table, const char *name,
                                type_suffix_t suffix, TNODE *tnode,
                                cexception_t *ex )
{
    cexception_t inner;
    TYPE_NODE * volatile node = NULL;
    TNODE *ret = NULL;

    assert( table );
    assert( name );

    cexception_guard( inner ) {
        node = new_type_node_default( ex );
        node->tnode = tnode;
        node->suffix = suffix;
        node->scope = table->current_scope;
        node->subscope = table->current_subscope;
        node->name  = strdupx( (char*)name, &inner );
        node->next  = table->node;
        table->node = node;
    }
    cexception_catch {
        delete_type_node( node );
	cexception_reraise( inner, ex );
    }
    return ret;
}

void typetab_copy_table( TYPETAB *dst, TYPETAB *src, cexception_t *ex )
{
    TYPE_NODE *curr;

    assert( dst );
    assert( src );

    for( curr = src->node; curr != NULL; curr = curr->next ) {
	char *name = curr->name;
	TNODE *tnode = curr->tnode;
	type_suffix_t suffix_type = curr->suffix;
	typetab_insert_suffix( dst, name, suffix_type, share_tnode( tnode ), ex );
    }
}

TNODE *typetab_lookup( TYPETAB *table, const char *name )
{
    return typetab_lookup_suffix( table, name, TS_NOT_A_SUFFIX );
}

TNODE *typetab_lookup_suffix( TYPETAB *table, const char *name,
			      type_suffix_t suffix )
{
    TYPE_NODE *node;
    assert( table );
    assert( name );
    for( node = table->node; node != NULL; node = node->next ) {
        if( strcmp( name, node->name ) == 0 && suffix == node->suffix ) {
	    assert( node->tnode );
	    return node->tnode;
	}
    }
    return NULL;
}

void typetab_begin_scope( TYPETAB* table, cexception_t *ex )
{
    assert( table );
    table->current_scope ++;
}

void typetab_end_scope( TYPETAB* table, cexception_t *ex )
{
    TYPE_NODE *tn, *next;

    assert( table );
    assert( table->current_scope > 0 );

    tn = table->node;
    while( tn != NULL ) {
        next = tn->next;
	if( table->current_scope != tn->scope ) {
	    break;
	} else {
	    delete_type_node( tn );
	}
	tn = next;
    }
    table->node = tn;
    table->current_scope --;
    return;
}

void typetab_begin_subscope( TYPETAB* table, cexception_t *ex )
{
    assert( table );
    table->current_subscope ++;
}

void typetab_end_subscope( TYPETAB* table, cexception_t *ex )
{
    TYPE_NODE *tn, *next;

    assert( table );

    tn = table->node;
    while( tn != NULL ) {
        next = tn->next;
	if( table->current_subscope != tn->subscope ) {
	    break;
	} else {
	    delete_type_node( tn );
	}
	tn = next;
    }
    table->node = tn;
    table->current_subscope --;
    return;
}
