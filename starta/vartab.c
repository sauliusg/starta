/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* symbol table to store defined variables */

/* exports: */
#include <vartab.h>

/* uses: */
#include <string.h> /* for strcmp() */
#include <dnode.h>
#include <tnode_compat.h>
#include <cexceptions.h>
#include <allocx.h>
#include <stringx.h>
#include <yy.h>
#include <assert.h>

typedef enum {
    VNF_NONE = 0,
    VNF_IS_IMPORTED /* identifies nodes imported from modules into
                       other namespaces. */
} var_node_flag_t;

typedef struct VAR_NODE {
    int flags;
    int count; /* counts how may times an object with this name was
                  imported from different modules. */
    int scope;
    int subscope;
    char *name;
    DNODE *dnode;
    struct VAR_NODE *next;
} VAR_NODE;

#include <varnode_a.ci>

static VAR_NODE *new_var_node_default( cexception_t *ex )
{
    return alloc_var_node( ex );
}

static VAR_NODE *new_var_node( DNODE *volatile *dnode,
                               const char* name,
                               int current_scope,
                               int current_subscope,
                               int count,
                               VAR_NODE *next_node,
                               cexception_t *ex )
{
    VAR_NODE *node = new_var_node_default( ex );
    assert( dnode );

    node->dnode = *dnode;
    node->name  = strdupx( (char*)name, ex );
    node->next  = next_node;
    node->scope = current_scope;
    node->count = count;
    node->subscope = current_subscope;
    dnode_set_scope( *dnode, current_scope );

    *dnode = NULL;
    return node;
}

static VAR_NODE *new_var_node_linked( VAR_NODE *next, cexception_t *ex )
{
    VAR_NODE *node = alloc_var_node( ex );
    node->next = next;
    return node;
}

static void delete_var_node( VAR_NODE *node )
{
    if( node ) {
	delete_dnode( node->dnode );
        freex( node->name );
        /* freex( node ); */
        free_var_node( node );
    }
}

static void delete_var_node_list( VAR_NODE *node )
{
    VAR_NODE *next;
    while( node ) {
        next = node->next;
	delete_var_node( node );
	node = next;
    }
}

struct VARTAB {
    int current_scope;
    int current_subscope;
    VAR_NODE *duplicates;
    VAR_NODE *node;
};

#include <vartab_a.ci>

VARTAB *new_vartab( cexception_t *ex )
{
    return alloc_vartab( ex );
}

void dispose_vartab( VARTAB *volatile *table )
{
    assert( table );
    delete_vartab( *table );
    *table = NULL;
}

void delete_vartab( VARTAB *table )
{
    if( !table ) return;
    delete_var_node_list( table->duplicates );
    delete_var_node_list( table->node );
    free_vartab( table );
}

void vartab_break_cycles( VARTAB *table )
{
    VAR_NODE *vnode;

    if( table ) {
        for( vnode = table->node; vnode != NULL; vnode = vnode->next ) {
            dnode_break_cycles( vnode->dnode );
        }
    }
}

int vartab_current_scope( VARTAB *vartab )
{
    assert( vartab );
    return vartab->current_scope;
}

void vartab_insert_operator( VARTAB *table, const char *name,
                             DNODE *volatile *dnode, cexception_t *ex )
{
    assert( table );
    assert( dnode );
    table->node = new_var_node( dnode, name,
                                table->current_scope,
                                table->current_subscope,
                                /* count = */ 1,
                                table->node, ex );
}

void vartab_insert_named_operator( VARTAB *table, DNODE *volatile *dnode,
                                   cexception_t *ex )
{
    assert( dnode );
    vartab_insert_operator( table, dnode_name( *dnode ), dnode, ex );
}

void vartab_insert_named_vars( VARTAB *table, DNODE *volatile *dnode_list,
			       cexception_t *ex )
{
    DNODE *dnode;
    DNODE *volatile shared_dnode = NULL;
    char *name;
    cexception_t inner;

    assert( dnode_list );
    assert( table );
    assert( dnode_list );

    cexception_guard( inner ) {
        dnode = *dnode_list;
        name = dnode_name( dnode );
        assert( name );
        shared_dnode = share_dnode( dnode );
        vartab_insert( table, name, &shared_dnode, &inner );

        while( ( dnode = dnode_next( dnode )) != NULL ) {
            name = dnode_name( dnode );
            assert( name );
            shared_dnode = share_dnode( dnode );
            vartab_insert( table, name, &shared_dnode, &inner );
        }
    }
    cexception_catch {
        dispose_dnode( dnode_list );
        delete_dnode( shared_dnode );
        cexception_reraise( inner, ex );
    }
    dispose_dnode( dnode_list );
}

void vartab_insert_named( VARTAB *table, DNODE *volatile *dnode, cexception_t *ex )
{
    assert( table );
    assert( dnode );
    vartab_insert( table, dnode_name(*dnode), dnode, ex );
}

static VAR_NODE *vartab_lookup_varnode( VARTAB *table, const char *name );

void vartab_insert( VARTAB *table, const char *name,
		    DNODE *volatile *dnode, cexception_t *ex )
{
    VAR_NODE * volatile node = NULL;
    assert( dnode );
    assert( table );

    if( (node = vartab_lookup_varnode( table, name )) != NULL ) {
        if( node->scope == table->current_scope &&
            (node->flags & VNF_IS_IMPORTED) == 0 ) {
            yyerrorf( "symbol '%s' already declared in the current scope",
                      name );
            table->duplicates =
                new_var_node_linked( table->duplicates, ex );
            table->duplicates->dnode = *dnode;
#if 0
        } else {
            fprintf( stderr, "name '%s' shadows previous declaration "
                     "in scope %d (currently in scope %d)\n",
                     name, node->scope, table->current_scope );
#endif
        }
    }
    if( !node || node->scope != table->current_scope ||
        (node->flags & VNF_IS_IMPORTED) != 0 ) {
        table->node = new_var_node( dnode, name,
                                    table->current_scope,
                                    table->current_subscope,
                                    /* count = */ 1,
                                    table->node, ex );
    }
    *dnode = NULL;
}

static
VAR_NODE *vartab_lookup_module_varnode( VARTAB *table, DNODE *module, 
                                        char *name, SYMTAB *symtab );

void vartab_insert_module( VARTAB *table, DNODE *volatile *module, char *name,
                           SYMTAB *st, cexception_t *ex )
{
    VAR_NODE * volatile node = NULL;
    int count = 0;
    assert( table );
    assert( module );

    vartab_lookup_silently( table, name, &count, /* &s_imported = */ NULL );

    if( (node = vartab_lookup_module_varnode( table, *module, name, st ))
        != NULL ) {
        if( node->scope == table->current_scope &&
            (node->flags & VNF_IS_IMPORTED) == 0 ) {
            yyerrorf( "symbol '%s' already declared in the current scope",
                      name );
            table->duplicates =
                new_var_node_linked( table->duplicates, ex );
            table->duplicates->dnode = *module;
        }
    }
    if( !node || node->scope != table->current_scope ||
        (node->flags & VNF_IS_IMPORTED) != 0 ) {
        table->node = new_var_node( module, name,
                                    table->current_scope,
                                    table->current_subscope,
#if 1
                                    /* count = */ count + 1,
#else
                                    1,
#endif
                                    table->node, ex );
    }
    *module = NULL;
}

void vartab_insert_named_module( VARTAB *table, DNODE *volatile *module,
                                 SYMTAB *st, cexception_t *ex )
{
    assert( module );
    char *name = dnode_name( *module );
    vartab_insert_module( table, module, name, st, ex );
}

void vartab_insert_modules_name( VARTAB *table, const char *name,
                                 DNODE *volatile *dnode, cexception_t *ex )
{
    VAR_NODE * volatile node = NULL;
    assert( table );
    assert( dnode );

    if( (node = vartab_lookup_varnode( table, name )) != NULL ) {
        if( node->scope == table->current_scope ) {
            if( (node->flags & VNF_IS_IMPORTED) == 0 ) {
                /* a non-imported name exists -- silently ignore
                   the imported name:*/
                table->duplicates =
                    new_var_node_linked( table->duplicates, ex );
                table->duplicates->dnode = *dnode;
            } else {
                /* another imported name exists: add the new
                   imported name, but mark that it is present
                   multiple times: */
                table->node = new_var_node( dnode, name,
                                            table->current_scope,
                                            table->current_subscope,
                                            node->count + 1,
                                            table->node, ex );

                table->node->flags |= VNF_IS_IMPORTED;
            }
        }
    }
    /* No node with the same name is present in the current scope:
       add it: */
    if( !node || node->scope != table->current_scope ) {
        table->node = new_var_node( dnode, name, 
                                    table->current_scope,
                                    table->current_subscope,
                                    /* count = */ 1,
                                    table->node, ex );

        table->node->flags |= VNF_IS_IMPORTED;
    }
    *dnode = NULL;
}

void vartab_copy_table( VARTAB *dst, VARTAB *src, cexception_t *ex )
{
    VAR_NODE *curr;
    DNODE *volatile shared_dnode = NULL;
    cexception_t inner;

    assert( dst );
    assert( src );

    cexception_guard( inner ) {
        for( curr = src->node; curr != NULL; curr = curr->next ) {
            char *name = curr->name;
            DNODE *dnode = curr->dnode;
            shared_dnode = share_dnode( dnode );
            vartab_insert_modules_name( dst, name, &shared_dnode, &inner );
        }
    }
    cexception_catch {
        delete_dnode( shared_dnode );
        cexception_reraise( inner, ex );
    }
}

DNODE *vartab_lookup( VARTAB *table, const char *name )
{
    VAR_NODE *node = vartab_lookup_varnode( table, name );
    if( node && node->count > 1 ) {
        yyerrorf( "name '%s' is imported more than once -- "
                  "please use explicit module name for disambiguation",
                  name );
    }
    return node ? node->dnode : NULL;
}

static
VAR_NODE *vartab_lookup_module_varnode( VARTAB *table, DNODE *module, 
                                        char *name, SYMTAB *symtab )
{
    VAR_NODE *node;
    char *module_name = name ? name : dnode_name( module );
    char *module_filename = module ? dnode_filename( module ) : NULL;

#if 0
    printf( "\n>>>> %s():\n", __FUNCTION__ );
#endif

    assert( table );
    for( node = table->node; node != NULL; node = node->next ) {
        char *table_filename =
            node->dnode ? dnode_filename( node->dnode ) : NULL;
#if 0
        printf( "vartab>>> now checking module '%s' (node name '%s'), "
                "filename '%s'\n",
                dnode_name( node->dnode ), node->name, 
                dnode_filename( node->dnode ));
#endif
        if( strcmp( module_name, node->name ) == 0 &&
            ( (!module_filename && !table_filename) ||
              (module_filename && table_filename &&
               strcmp( module_filename, table_filename ) == 0 ))) {
	    assert( node->dnode );
            if( dnode_module_args_are_identical( node->dnode, module,
                                                 symtab ) ) {
                return node;
            }
	}
    }
    return NULL;
}

DNODE *vartab_lookup_module( VARTAB *table, DNODE *module, SYMTAB *symtab )
{
    VAR_NODE *node =
        vartab_lookup_module_varnode( table, module, NULL, symtab );
    return node ? node->dnode : NULL;
}

DNODE *vartab_lookup_silently( VARTAB *table, const char *name, 
                               int *count, int *is_imported )
{
    VAR_NODE *node = vartab_lookup_varnode( table, name );
    if( node ) {
        if( count )
            *count = node->count;
        if( is_imported ) 
            *is_imported = ((node->flags & VNF_IS_IMPORTED) != 0);
    }
    return node ? node->dnode : NULL;
}

static VAR_NODE *vartab_lookup_varnode( VARTAB *table, const char *name )
{
    VAR_NODE *node;
    assert( table );
    if( !name )
        return NULL;
    for( node = table->node; node != NULL; node = node->next ) {
        if( strcmp( name, node->name ) == 0 ) {
	    assert( node->dnode );
	    return node;
	}
    }
    return NULL;
}

DNODE *vartab_lookup_operator( VARTAB *table, const char *name,
                               TLIST *argument_types )
{
    VAR_NODE *node;
    TLIST *current_arg;
    int found = 0;

    assert( table );
    for( node = table->node; node != NULL; node = node->next ) {
        assert( node->dnode );
        if( strcmp( name, node->name ) == 0 ) {
            TNODE *operator_type = dnode_type( node->dnode );
            DNODE *parameter = operator_type ?
                tnode_args( operator_type ) : NULL;
            found = 0;
            {
                cexception_t inner;
                TYPETAB *volatile generic_types = NULL;

                cexception_guard( inner ) {
                    TNODE *argument_type, *parameter_type;
                    generic_types = new_typetab( &inner );
                    foreach_tlist( current_arg, argument_types ) {
                        found = 1;
                        if( !parameter ) {
                            found = 0;
                            break;
                        }
                        argument_type = tlist_data( current_arg );
                        parameter_type = dnode_type( parameter );
                        if( !tnode_types_are_identical( argument_type,
                                                        parameter_type,
                                                        generic_types,
                                                        &inner )) {
                            found = 0;
                            break;
                        }
                        parameter = dnode_next( parameter );
                    }
                }
                delete_typetab( generic_types );
            }
            if( found ) {
                return node->dnode;
            }
	}
    }
    return NULL;
}

void vartab_begin_scope( VARTAB* table, cexception_t *ex )
{
    assert( table );
    table->current_scope ++;
}

void vartab_end_scope( VARTAB* table, cexception_t *ex )
{
    VAR_NODE *tn, *next;

    assert( table );
    assert( table->current_scope > 0 );

    tn = table->node;
    while( tn != NULL ) {
        next = tn->next;
	if( table->current_scope != tn->scope ) {
	    break;
	} else {
	    delete_var_node( tn );
	}
	tn = next;
    }
    table->node = tn;

    assert( table->current_scope > 0 );
    table->current_scope --;
    return;
}

void vartab_begin_subscope( VARTAB* table, cexception_t *ex )
{
    assert( table );
    table->current_subscope ++;
}

void vartab_end_subscope( VARTAB* table, cexception_t *ex )
{
    VAR_NODE *tn, *next;

    assert( table );

    tn = table->node;
    while( tn != NULL ) {
        next = tn->next;
	if( table->current_subscope != tn->subscope  ) {
	    break;
	} else {
	    delete_var_node( tn );
	}
	tn = next;
    }
    table->node = tn;
    assert( table->current_subscope > 0 );
    table->current_subscope --;
    return;
}
