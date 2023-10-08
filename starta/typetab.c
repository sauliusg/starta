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

typedef enum {
    TNF_NONE = 0,
    TNF_IS_IMPORTED /* identifies nodes imported from modules into
                       other namespaces. */
} type_node_flag_t;

typedef struct TYPE_NODE {
    int flags;
    int count; /* counts how may times a type node with this name was
                  imported from different modules. */
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

static TYPE_NODE *new_type_node( TNODE *tnode, const char* name,
                                 type_suffix_t suffix,
                                 int current_scope,
                                 int current_subscope,
                                 int count,
                                 TYPE_NODE *next_node,
                                 cexception_t *ex )
{
    TYPE_NODE *node = new_type_node_default( ex );

    node->tnode = tnode;
    node->name  = strdupx( (char*)name, ex );
    node->suffix = suffix;
    node->scope = current_scope;
    node->subscope = current_subscope;
    node->count = count;
    node->next  = next_node;

    return node;
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

void dispose_typetab( TYPETAB *volatile *table )
{
    assert( table );
    delete_typetab( *table );
    *table = NULL;
}

void delete_typetab( TYPETAB *table )
{
    if( !table ) return;
    delete_type_node_list( table->node );
    freex( table );
}

void typetab_break_cycles( TYPETAB *table )
{
    TYPE_NODE *node;

    if( table ) {
        for( node = table->node; node != NULL; node = node->next ) {
            tnode_break_cycles( node->tnode );
        }
    }
}

void typetab_traverse_tnodes_and_set_rcount2( TYPETAB *table )
{
    TYPE_NODE *node;

    if( table ) {
        for( node = table->node; node != NULL; node = node->next ) {
            tnode_traverse_rcount2( node->tnode );
        }
    }
}

void typetab_traverse_tnodes_and_mark_accessible( TYPETAB *table )
{
    TYPE_NODE *node;

    if( table ) {
        for( node = table->node; node != NULL; node = node->next ) {
            tnode_mark_accessible( node->tnode );
        }
    }
}

TNODE *typetab_insert( TYPETAB *table, const char *name,
		       TNODE *volatile *tnode, cexception_t *ex )
{
    return typetab_insert_suffix( table, name, TS_NOT_A_SUFFIX, tnode, 
                                  /* count = */ NULL,
                                  /* is_imported = */ NULL,
                                  ex );
}

static TYPE_NODE *typetab_lookup_typenode( TYPETAB *table, const char *name,
                                           type_suffix_t suffix );

TNODE *typetab_insert_suffix( TYPETAB *table, const char *name,
			      type_suffix_t suffix, TNODE *volatile *tnode,
                              int *count, int *is_imported,
			      cexception_t *ex )
{
    TNODE *ret = NULL;
    TYPE_NODE *lookup_node = NULL;

    assert( table );
    assert( name );

    lookup_node = typetab_lookup_typenode( table, name, suffix );

    if( lookup_node && lookup_node->scope == table->current_scope &&
        lookup_node->subscope == table->current_subscope ) {
        if( count )
            *count = lookup_node->count;
        if( is_imported ) 
            *is_imported = ((lookup_node->flags & TNF_IS_IMPORTED) != 0);
        if( (lookup_node->flags & TNF_IS_IMPORTED) == 0 ) {
            /* The node found is not imported -- it is a genuine
               duplicate; we discard the submitted tnode and return
               the found one: */
            ret = lookup_node->tnode;
            dispose_tnode( tnode );
        } else {
            /* We mask the imported node and insert the newly created
               one: */
            table->node = new_type_node( *tnode, name, suffix,
                                         table->current_scope,
                                         table->current_subscope,
                                         /* count = */ 1,
                                         /* next = */ table->node, ex );
            ret = *tnode;
            *tnode = NULL;
        }
    } else {
        if( count ) *count = 1;
        if( is_imported ) *is_imported = 0;
        table->node = new_type_node( *tnode, name, suffix,
                                     table->current_scope,
                                     table->current_subscope,
                                     /* count = */ 1,
                                     /* next = */ table->node, ex );
        ret = *tnode;
        *tnode = NULL;
    }

    assert(!*tnode);
    return ret;
}

static TNODE *typetab_insert_imported_suffix( TYPETAB *table, const char *name,
                                              type_suffix_t suffix,
                                              TNODE *volatile *tnode,
                                              cexception_t *ex )
{
    TNODE *ret = NULL;
    TYPE_NODE *lookup_node = NULL;

    assert( tnode );
    assert( table );
    assert( name );

    lookup_node = typetab_lookup_typenode( table, name, suffix );

    if( lookup_node && lookup_node->scope == table->current_scope ) {
        assert( lookup_node->tnode );
        if( !tnode_is_forward( lookup_node->tnode )) {
            if( (lookup_node->flags & TNF_IS_IMPORTED) == 0 ) {
                /* a non-imported name exists in the same scope --
                   silently ignore the imported name:*/
                ret = lookup_node->tnode;
                dispose_tnode( tnode );
            } else {
                /* another imported type name exists: add the new
                   imported name, but mark that it is present
                   multiple times: */
                table->node = new_type_node( *tnode, name, suffix,
                                             table->current_scope,
                                             table->current_subscope,
                                             lookup_node->count + 1,
                                             /* next = */ table->node,
                                             ex );
                table->node->flags |= TNF_IS_IMPORTED;
                *tnode = NULL;
            }
        } else {
            /* A forward declaration must be overriden: */
            ret = lookup_node->tnode;
            *tnode = NULL;
        }
    } else {
        /* No node with the same name is present in the current scope:
           add it: */
        table->node = new_type_node( *tnode, name, suffix,
                                     table->current_scope,
                                     table->current_subscope,
                                     /* count = */ 1,
                                     /* next = */ table->node, ex );
        table->node->flags |= TNF_IS_IMPORTED;
        ret = *tnode;
        *tnode = NULL;
    }

    assert( !*tnode );
    return ret;
}

void typetab_override_suffix( TYPETAB *table, const char *name,
                              type_suffix_t suffix, TNODE *volatile *tnode,
                              cexception_t *ex )
{
    assert( tnode );
    assert( table );
    assert( name );
    assert( *tnode );
    table->node = new_type_node( *tnode, name, suffix,
                                 table->current_scope,
                                 table->current_subscope,
                                 /* count = */ 1,
                                 /* next = */ table->node, ex );
    *tnode = NULL;
}

TNODE *typetab_lookup_type_pair( TYPETAB *table, const TNODE *generic_type,
                                 cexception_t *ex )
{
    TYPE_NODE *node;
    assert( table );
    assert( generic_type );
    for( node = table->node; node != NULL; node = node->next ) {
        if( node->tnode &&
            tnode_generic_type( node->tnode ) == generic_type ) {
	    return node->tnode;
	}
    }
    return NULL;
}

TNODE *typetab_lookup_paired_type( TYPETAB *table, const TNODE *generic_type,
                                   cexception_t *ex )
{
    TNODE *tnode = typetab_lookup_type_pair( table, generic_type, ex );
    if( tnode ) {
        return tnode_concrete_type( tnode );
    } else {
        return NULL;
    }
}

TNODE *typetab_insert_type_pair( TYPETAB *table,
                                 TNODE *volatile *generic_type,
                                 TNODE *volatile *concrete_type,
                                 cexception_t *ex )
{
    TNODE *volatile type_pair =
        new_tnode_type_pair( generic_type, concrete_type, ex );

    return typetab_insert( table, /*name =*/ NULL, &type_pair, ex );
}

void typetab_copy_table( TYPETAB *dst, TYPETAB *src, cexception_t *ex )
{
    TYPE_NODE *curr;
    TNODE *volatile shared_tnode = NULL;
    cexception_t inner;

    assert( dst );
    assert( src );

    cexception_guard( inner ) {
        for( curr = src->node; curr != NULL; curr = curr->next ) {
            char *name = curr->name;
            TNODE *tnode = curr->tnode;
            type_suffix_t suffix_type = curr->suffix;
            shared_tnode = share_tnode( tnode );
            typetab_insert_imported_suffix( dst, name, suffix_type,
                                            &shared_tnode, &inner );
        }
    }
    cexception_catch {
        delete_tnode( shared_tnode );
        cexception_reraise( inner, ex );
    }
}

TNODE *typetab_lookup( TYPETAB *table, const char *name )
{
    return typetab_lookup_suffix( table, name, TS_NOT_A_SUFFIX );
}

static TYPE_NODE *typetab_lookup_typenode( TYPETAB *table, const char *name,
                                           type_suffix_t suffix )
{
    TYPE_NODE *node;
    assert( table );
    assert( name );
    for( node = table->node; node != NULL; node = node->next ) {
        if( strcmp( name, node->name ) == 0 && suffix == node->suffix ) {
	    return node;
	}
    }
    return NULL;
}

TNODE *typetab_lookup_suffix( TYPETAB *table, const char *name,
			      type_suffix_t suffix )
{
    TYPE_NODE *node = typetab_lookup_typenode( table, name, suffix );

    if( node ) {
        if( node && node->count > 1 ) {
            if( name && name[0] != '\0' ) {
                yyerrorf( "type '%s' is imported more than once "
                          "-- please use explicit package name "
                          "for disambiguation", name );
            } else {
                TNODE *tnode = node->tnode;
                yyerrorf( "type with empty suffix is imported more than once "
                          "(in one instance as type '%s' of kind '%s') -- "
                          "please use explicit package name "
                          "for disambiguation",
                          tnode_name( tnode ), tnode_kind_name( tnode ) );
            }
        }
        assert( node->tnode );
        return node->tnode;
    } else {
        return NULL;
    }
}

TNODE *typetab_lookup_suffix_silently( TYPETAB *table, const char *name,
                                       type_suffix_t suffix )
{
    TYPE_NODE *node = typetab_lookup_typenode( table, name, suffix );

    if( node ) {
        assert( node->tnode );
        return node->tnode;
    } else {
        return NULL;
    }
}

TNODE *typetab_lookup_silently( TYPETAB *table, const char *name )
{
    return typetab_lookup_suffix_silently( table, name, TS_NOT_A_SUFFIX );
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
