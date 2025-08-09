/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <tnode_compat.h>

/* uses: */
#include <tnode.ci>
#include <string.h>
#include <stdio.h>
#include <limits.h> /* for CHAR_BIT */
#include <yy.h>
#include <assert.h>

static int tnode_structures_are_compatible( TNODE *t1, TNODE *t2,
					    TYPETAB *generic_types,
                                            char *msg, ssize_t msglen,
					    cexception_t *ex )
{
    DNODE *f1, *f2;
    TNODE *tf1, *tf2;

    f1 = t1->fields;
    f2 = t2->fields;
    while( f1 && f2 ) {
	tf1 = dnode_type( f1 );
	tf2 = dnode_type( f2 );
        if( tf1 && tf2 && 
            ( tnode_kind( tf1 ) == TK_PLACEHOLDER ||
              tnode_kind( tf2 ) == TK_PLACEHOLDER )) {
            ssize_t bytes = sizeof(ssize_t);
            ssize_t bits = (CHAR_BIT * bytes)/2;
            size_t mask = ~(~((ssize_t)0) << bits);
            ssize_t offs1 = dnode_offset( f1 );
            ssize_t offs2 = dnode_offset( f2 );
            //printf( ">>> mask = 0x%08X\n", mask );
            if( tnode_kind( tf1 ) == TK_PLACEHOLDER ) {
                offs1 &= mask;
            }
            if( tnode_kind( tf2 ) == TK_PLACEHOLDER ) {
                offs2 &= mask;
            }
            //printf( ">>> f1 offset = %d\n", offs1 );
            //printf( ">>> f2 offset = %d\n\n", offs2 );
            if( offs1 > 0 && offs2 > 0 && offs1 != offs2 ) {
                if( msg && msglen != 0 ) {
                    snprintf( msg, msglen, "offset of the generic field '%s' "
                              "is incompatible with the concrete implementation",
                              dnode_name( f1 ));
                }
                return 0;
            }
        }
	if( !tnode_types_are_compatible( tf1, tf2, generic_types, ex )) {
	    return 0;
	}
	f1 = dnode_next( f1 );
	f2 = dnode_next( f2 );
    }
    if( !f1 && !f2 ) {
	return 1;
    } else {
	return 0;
    }
}

int tnode_function_prototypes_match_msg( TNODE *f1, TNODE *f2,
					 char *msg, int msglen );

static int tnode_classes_are_compatible( TNODE *t1, TNODE *t2,
					 TYPETAB *generic_types,
                                         char *msg, int msglen ,
					 cexception_t *ex )
{
    DNODE *t1_method, *t2_method;
    long nmethods1, nmethods2;

    if( !t1 && !t2 ) return 1;
    if( !t1 || !t2 ) return 0;

    t2_method = t2->methods;

    nmethods1 = dnode_list_length( t1->methods );
    nmethods2 = dnode_list_length( t2->methods );

    if( nmethods1 != nmethods2 ) {
        char *name1 = tnode_name( t1 );
        char *name2 = tnode_name( t2 );
        if( name1 && name2 ) {
            yyerrorf( "classes '%s' and '%s' have different number of methods",
                      name1, name2 );
        } else {
            yyerrorf( "classes have different number of methods" );            
        }
        return 0;
    }

    for( t1_method = t1->methods; t1_method && t2_method;
         t1_method = dnode_next( t1_method )) {
        TNODE *t1_method_type = dnode_type( t1_method );
        TNODE *t2_method_type = dnode_type( t2_method );
        char msg[100];
        if( !tnode_function_prototypes_match_msg
            ( t1_method_type, t2_method_type, msg, sizeof(msg)-1 )) {
            yyerrorf( "incompatible class method '%s' ('%s'): %s", 
                      dnode_name( t1_method ),
                      dnode_name( t2_method ),
                      msg );
            return 0;
        }
        t2_method = dnode_next( t2_method );
    }

    return
        tnode_structures_are_compatible( t1, t2, generic_types, 
                                         msg, msglen, ex ) &&
        tnode_classes_are_compatible( t1->base_type, t2->base_type,
				      generic_types, msg, msglen, ex );
}

static int tnode_structures_are_identical( TNODE *t1, TNODE *t2,
					   TYPETAB *generic_types,
					   cexception_t *ex )
{
    DNODE *f1, *f2;
    TNODE *tf1, *tf2;

    f1 = t1->fields;
    f2 = t2->fields;
    while( f1 && f2 ) {
	tf1 = dnode_type( f1 );
	tf2 = dnode_type( f2 );
	if( !tnode_types_are_identical( tf1, tf2, generic_types, ex )) {
	    return 0;
	}
	f1 = dnode_next( f1 );
	f2 = dnode_next( f2 );
    }
    if( !f1 && !f2 ) {
	return 1;
    } else {
	return 0;
    }
}

static int
tnode_create_and_check_placeholder_implementation( TNODE *t1, TNODE *t2,
                                                   TYPETAB *generic_types,
                                                   int (*tnode_check_types)
                                                       ( TNODE *t1, TNODE *t2,
                                                         TYPETAB *generic_types,
                                                         cexception_t *ex ),
                                                   cexception_t *ex)
{
    TNODE *volatile shared_t1 = NULL;
    TNODE *volatile placeholder_implementation = t2->name ?
        typetab_lookup( generic_types, t2->name ) : NULL;

    if( placeholder_implementation ) {
        return tnode_check_types
            ( t1, placeholder_implementation->base_type,
              generic_types, ex );
    } else {
        cexception_t inner;
        cexception_guard( inner ) {
            placeholder_implementation =
                new_tnode_placeholder( t2->name, &inner );
            shared_t1 = share_tnode( t1 );
            tnode_insert_base_type( placeholder_implementation,
                                    &shared_t1 );
            typetab_insert( generic_types, t2->name,
                            &placeholder_implementation, &inner );
        }
        cexception_catch {
            delete_tnode( shared_t1 );
            delete_tnode( placeholder_implementation );
            cexception_reraise( inner, ex );
        }
        return 1;
    }
}

static int
tnode_check_generic_compatibility( TNODE *generic_type,
                                   TNODE *implementing_type )
{
    assert( generic_type );
    assert( implementing_type );

    while( generic_type != NULL &&
           tnode_kind( generic_type ) == TK_GENERIC ) {
        generic_type = tnode_base_type( generic_type );
    }

    TNODE *t1 = generic_type;
    TNODE *t2 = implementing_type;

    // printf(">>>> Adding generic implementation for:\n");
    // printf(">>>> t1 name: '%s'\n", tnode_name(t1));
    // printf(">>>> t2 name: '%s'\n", tnode_name(t2));
    // printf(">>>> t1 kind: '%s'\n", tnode_kind_name(t1));
    // printf(">>>> t2 kind: '%s'\n", tnode_kind_name(t2));

    if( tnode_is_reference(t1) &&
        tnode_is_reference(t2) ) {
        return 1;
    }
    
    if( tnode_is_reference(t1) &&
        tnode_is_reference(t2) ) {
        return 1;
    }
    
    return 0;
}

static int
tnode_create_and_check_generic_types( TNODE *t1, TNODE *t2,
                                      TYPETAB *generic_types,
                                      int (*tnode_check_types)
                                          ( TNODE *t1, TNODE *t2,
                                            TYPETAB *generic_types,
                                            cexception_t *ex ),
                                      cexception_t *ex )
{
    if( generic_types && ( t1->params.kind == TK_PLACEHOLDER ||
			   t2->params.kind == TK_PLACEHOLDER )) {
        if( t2->params.kind == TK_PLACEHOLDER ) {
            if( t2->base_type ) {
                /* placeholder is already implemented: */
                return tnode_check_types
                    ( t1, t2->base_type, generic_types, ex );
            } else {
                return tnode_create_and_check_placeholder_implementation
                    ( t2, t1, generic_types, tnode_check_types, ex );
            }
        } else {
            return tnode_create_and_check_placeholder_implementation
                ( t2, t1, generic_types, tnode_check_types, ex );
        }
    } else
    if( generic_types && ( t1->params.kind == TK_NOMINAL ||
			   t2->params.kind == TK_NOMINAL )) {
        if( t2->params.kind == TK_NOMINAL ) {
            if( t2->base_type ) {
                /* placeholder is already implemented: */
                return tnode_check_types
                    ( t1, t2->base_type, generic_types, ex );
            } else {
                return tnode_create_and_check_placeholder_implementation
                    ( t2, t1, generic_types, tnode_check_types, ex );
            }
        } else {
            return tnode_create_and_check_placeholder_implementation
                ( t2, t1, generic_types, tnode_check_types, ex );
        }
    } else if( generic_types && t1->params.kind == TK_GENERIC ) {
        TNODE *concrete_type = typetab_lookup_paired_type( generic_types, t1 );

        if( concrete_type ) {
            return tnode_check_types( concrete_type, t2, generic_types, ex );
        } else {
            cexception_t inner;
            TNODE *volatile generic_type = share_tnode( t1 );
            TNODE *volatile implementation_type = share_tnode( t2 );
            cexception_guard( inner ) {
                if( !tnode_check_generic_compatibility
                    ( generic_type, implementation_type )) {
                    return 0;
                }; 
                typetab_insert_type_pair( generic_types, &generic_type,
                                          &implementation_type, &inner );
                return 1;
            }
            cexception_catch {
                delete_tnode( generic_type );
                delete_tnode( implementation_type );
                cexception_reraise( inner, ex );
            }
        }
    }

    return 0;
}

static int
tnode_implements_interface( TNODE *class_tnode, TNODE *interface_tnode )
{
    TLIST *curr;

    assert( class_tnode );
    foreach_tlist( curr, class_tnode->interfaces ) {
        TNODE *curr_tnode = tlist_data( curr );
        if( curr_tnode == interface_tnode ) {
            return 1;
        } else if( curr_tnode->base_type ) {
            TNODE *base;
            for( base = curr_tnode->base_type; base;
                 base = base->base_type ) {
                if( base == interface_tnode ) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

static int tnode_generic_function_prototypes_match( TNODE *f1, TNODE *f2,
                                                    TYPETAB *generic_types,
                                                    char *msg, int msglen,
                                                    cexception_t *ex );

static int
tnode_check_type_identity( TNODE *t1, TNODE *t2,
                           TYPETAB *generic_types,
                           cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;
    if( t1->params.kind == TK_IGNORE || t2->params.kind == TK_IGNORE ) {
	return 1;
    }

    if( t1->params.kind == TK_NOMINAL && t2->params.kind == TK_NOMINAL ) {
        if( strcmp(t1->name, t2->name) == 0 ) {
            return 1;
        } else {
            return 0;
        }
    }
    
    if( t1->params.kind == TK_REF ) {
	return tnode_is_reference( t2 );
    }
    // FIXME: too relaxed, should transfer these two TK_REF checks to
    // the 'types are compatible' or 'types are assignment compatible'
    // checks, and require strict equivalence, t{1,2}->params.kind == TK_REF,
    // here (S.G.):
    if( t2->params.kind == TK_REF ) {
	return tnode_is_reference( t1 );
    }
    if( t1->params.kind == TK_BLOB && t2->params.kind == TK_BLOB ) {
	return 1;
    }
    if( t1->params.kind == TK_NULLREF ) {
	return tnode_is_reference( t2 );
    }
    if( t2->params.kind == TK_NULLREF ) {
	return tnode_is_reference( t1 );
    }

    if( t1->params.kind == TK_INTERFACE && t2->params.kind == TK_CLASS ) {
	return tnode_implements_interface( t2, t1 );
    }

    if( t1->params.kind == TK_OPERATOR && t2->params.kind == TK_OPERATOR ) {
        return
	    dnode_lists_are_type_identical( t1->args, t2->args,
					    generic_types, ex ) &&
	    dnode_lists_are_type_identical( t1->return_vals,
					    t2->return_vals,
					    generic_types, ex );
    }

    if( t1->params.kind == TK_GENERIC ||
        t1->params.kind == TK_PLACEHOLDER ||
        t2->params.kind == TK_PLACEHOLDER ||
        t1->params.kind == TK_NOMINAL ||
        t2->params.kind == TK_NOMINAL ) {
        if( generic_types ) {
            return tnode_create_and_check_generic_types
                ( t1, t2, generic_types, tnode_types_are_identical, ex );
        } else {
            return 0;
        }
    }

    if( t1->params.kind == TK_COMPOSITE && t2->params.kind == TK_COMPOSITE ) {
	if( (t1->element_type && t1->element_type->params.kind == TK_PLACEHOLDER) &&
	    (t2->element_type && t2->element_type->params.kind == TK_PLACEHOLDER) ) {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0);
	} else {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0) &&
		tnode_types_are_identical( t1->element_type, t2->element_type,
					   generic_types, ex );
	}
    }

    if( t1->params.kind == TK_FUNCTION_REF && 
        (t2->params.kind == TK_FUNCTION || t2->params.kind == TK_CLOSURE )) {
	return tnode_generic_function_prototypes_match( t1, t2, generic_types,
                                                        NULL, 0, ex );
    }

    if( t1->params.kind == TK_FUNCTION_REF && t2->params.kind == TK_FUNCTION_REF ) {
	return tnode_generic_function_prototypes_match( t1, t2, generic_types,
                                                        NULL, 0, ex );
    }

    if( t1->name && t2->name ) return 0;
    if( (t1->params.kind == TK_ARRAY && t2->params.kind == TK_ARRAY) ||
	(t1->params.kind == TK_ADDRESSOF && t2->params.kind == TK_ADDRESSOF) ) {
	if( t1->element_type == NULL || t2->element_type == NULL ) {
	    return 1;
	} else {
	    return 
		tnode_types_are_identical( t1->element_type, t2->element_type,
					   generic_types, ex );
	}
    }
    if( t1->params.kind == TK_STRUCT && t2->params.kind == TK_STRUCT ) {
	return tnode_structures_are_identical( t1, t2,
					       generic_types, ex );
    }

    return 0;
}

int tnode_types_are_identical( TNODE *t1, TNODE *t2,
			       TYPETAB *generic_types,
			       cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;
    if( t1->params.kind == TK_IGNORE || t2->params.kind == TK_IGNORE ) {
	return 1;
    }

    if( t1->params.kind == TK_NOMINAL && t2->params.kind == TK_NOMINAL ) {
        if( strcmp(t1->name, t2->name) == 0 ) {
            return 1;
        } else {
            if( generic_types ) {
                return tnode_create_and_check_placeholder_implementation
                    ( t2, t1, generic_types, tnode_types_are_identical, ex );
            } else {
                return 0;
            }
        }
    }
    
    if( t1->params.kind == TK_DERIVED && tnode_has_flags( t1, TF_IS_EQUIVALENT )) {
        return tnode_types_are_identical( t1->base_type, t2, 
                                          generic_types, ex );
    }
    if( t2->params.kind == TK_DERIVED && tnode_has_flags( t2, TF_IS_EQUIVALENT )) {
        return tnode_types_are_identical( t1, t2->base_type, 
                                          generic_types, ex );
    }

    if( (t1->params.kind == TK_NULLREF && tnode_is_non_null_reference( t2 )) ||
        (t2->params.kind == TK_NULLREF && tnode_is_non_null_reference( t1 ))) {
        return 0;
    }

    return tnode_check_type_identity( t1, t2, generic_types, ex );
}

int tnode_types_are_compatible( TNODE *t1, TNODE *t2,
				TYPETAB *generic_types,
				cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;

    if( tnode_types_are_identical( t1, t2, generic_types, ex )) {
        return 1;
    }

    if( tnode_is_non_null_reference( t1 )) {
        if( !tnode_is_non_null_reference( t2 )) {
            return 0;
        }
    }

    if( t1->params.kind == TK_CLASS && t2->params.kind == TK_CLASS ) {
        return tnode_types_are_compatible( t1, t2->base_type,
                                           generic_types, ex );
    }
    
    if( t1->params.kind == TK_ENUM && t2->params.kind != TK_ENUM ) {
	return tnode_types_are_identical( t1->base_type, t2,
					  generic_types, ex );
    }
    if( t2->params.kind == TK_ENUM && t1->params.kind != TK_ENUM ) {
	return tnode_types_are_identical( t1, t2->base_type,
					  generic_types, ex );
    }

    return 0;
}

static int
tnode_types_are_contravariant( TNODE *t1, TNODE *t2,
                               TYPETAB *generic_types,
                               cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;

    if( tnode_types_are_identical( t1, t2, generic_types, ex )) {
        return 1;
    }

    if( tnode_is_non_null_reference( t1 )) {
        if( !tnode_is_non_null_reference( t2 )) {
            return 0;
        }
    }

    if( t1->params.kind == TK_CLASS && t2->params.kind == TK_CLASS ) {
        return tnode_types_are_identical
            ( t1->base_type, t2, generic_types, ex ) &&
            t1->base_type &&
            tnode_kind( t1->base_type ) != TK_REF;
    }
    
    if( t1->params.kind == TK_ENUM && t2->params.kind != TK_ENUM ) {
	return tnode_types_are_identical( t1->base_type, t2,
					  generic_types, ex );
    }
    if( t2->params.kind == TK_ENUM && t1->params.kind != TK_ENUM ) {
	return tnode_types_are_identical( t1, t2->base_type,
					  generic_types, ex );
    }

    return 0;
}

static int
tnode_generic_functions_are_assignment_compatible( TNODE *f1, TNODE *f2,
                                                   TYPETAB *generic_types,
                                                   char *msg, int msglen,
                                                   cexception_t *ex );

int tnode_types_are_assignment_compatible( TNODE *t1, TNODE *t2,
                                           TYPETAB *generic_types,
                                           char *msg, ssize_t msglen,
                                           cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;

    if( t1->params.kind == TK_DERIVED && tnode_has_flags( t1, TF_IS_EQUIVALENT )) {
        return tnode_types_are_assignment_compatible
            ( t1->base_type, t2, generic_types, msg, msglen, ex );
    }
    if( t2->params.kind == TK_DERIVED && tnode_has_flags( t2, TF_IS_EQUIVALENT )) {
        return tnode_types_are_assignment_compatible
            ( t1, t2->base_type, generic_types, msg, msglen, ex );
    }

    if( t1->params.kind == TK_ARRAY && t1->element_type == NULL &&
        t2->params.kind == TK_DERIVED ) {
        return tnode_types_are_assignment_compatible
            ( t1, t2->base_type, generic_types,
              msg, msglen, ex );
    }

    if( tnode_is_non_null_reference( t1 ) &&
        !tnode_is_non_null_reference( t2 )) {
        return 0;
    }

    if( t1->params.kind == TK_REF ) {
        return tnode_is_reference( t2 );
    }
    // if( t2->params.kind == TK_REF ) {
    //     return t1->params.kind == TK_REF;
    // }
    if( t1->params.kind == TK_BLOB && t2->params.kind == TK_BLOB ) {
	return 1;
    }
    if( t2->params.kind == TK_NULLREF ) {
        if( generic_types && t1->params.kind == TK_NOMINAL ) {
            return tnode_create_and_check_generic_types
                ( t1, t2, generic_types, tnode_types_are_identical, ex );
        } else {
            return tnode_is_reference( t1 );
        }
    }

    if( t1->params.kind == TK_STRUCT && t2->params.kind == TK_STRUCT ) {
	return tnode_structures_are_compatible( t1, t2, generic_types, 
                                                msg, msglen, ex ) ||
            tnode_structures_are_compatible( t1, t2->base_type,
                                             generic_types,
                                             msg, msglen, ex ) ||
            tnode_types_are_assignment_compatible( t1, t2->base_type,
                                                   generic_types, msg, msglen,
                                                   ex );
    }

    if( t1->params.kind == TK_CLASS && t2->params.kind == TK_CLASS ) {
        return (!t1->name && tnode_classes_are_compatible( t1, t2,
							   generic_types,
                                                           msg, msglen,
							   ex )) ||
            tnode_types_are_assignment_compatible( t1, t2->base_type,
                                                   generic_types,
                                                   msg, msglen, ex );
    }

    if( t1->params.kind == TK_INTERFACE && t2->params.kind == TK_INTERFACE ) {
        return (!t1->name && tnode_classes_are_compatible( t1, t2,
							   generic_types,
                                                           msg, msglen,
							   ex )) ||
            tnode_types_are_assignment_compatible( t1, t2->base_type,
                                                   generic_types,
                                                   msg, msglen, ex );
    }

    if( t1->params.kind == TK_INTERFACE && t2->params.kind == TK_CLASS ) {
	return tnode_implements_interface( t2, t1 );
    }

    if( t1->params.kind == TK_GENERIC ||
        t1->params.kind == TK_PLACEHOLDER ||
        t2->params.kind == TK_PLACEHOLDER ||
        t1->params.kind == TK_NOMINAL ||
        t2->params.kind == TK_NOMINAL ) {
        if( generic_types ) {
            return tnode_create_and_check_generic_types
                ( t1, t2, generic_types, tnode_types_are_identical, ex );
        } else {
            return 0;
        }
    }

    if( t1->params.kind == TK_COMPOSITE && t2->params.kind == TK_COMPOSITE ) {
	if( (t1->element_type && t1->element_type->params.kind == TK_PLACEHOLDER) &&
	    (t2->element_type && t2->element_type->params.kind == TK_PLACEHOLDER) ) {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0);
	} else {
            if( t2->element_type &&
                t2->element_type->params.kind == TK_PLACEHOLDER &&
                t1->base_type ) {
                return
                    tnode_types_are_assignment_compatible
                    ( t1->base_type, t2, generic_types, msg, msglen, ex );
            } else {
                return (!t1->name || !t2->name ||
                        strcmp( t1->name, t2->name ) == 0) &&
                    /* tnode_types_are_identical( t1->element_type,
                       t2->element_type ); */
                    tnode_types_are_assignment_compatible
                    ( t1->element_type, t2->element_type, generic_types,
                      msg, msglen, ex );
            }
        }
    }

    if( t1->params.kind == TK_FUNCTION_REF && 
        (t2->params.kind == TK_FUNCTION || t2->params.kind == TK_CLOSURE )) {
	return tnode_generic_functions_are_assignment_compatible
            ( t1, t2, generic_types, NULL, 0, ex );
    }

    if( t1->name && t2->name ) return 0;

    if( t1->params.kind == TK_FUNCTION_REF && t2->params.kind == TK_FUNCTION_REF ) {
	return tnode_generic_functions_are_assignment_compatible
            ( t1, t2, generic_types, NULL, 0, ex );
    }

    if( t1->params.kind == TK_ARRAY && t2->params.kind == TK_ARRAY ) {
	if( t1->element_type == NULL ) {
	    return t2->params.kind == TK_ARRAY;
	} else {
	    return tnode_types_are_identical
                ( t1->element_type, t2->element_type, generic_types, ex );
	}
    }

    return 0;
}

static TNODE *tnode_placeholder_implementation( TNODE *abstract,
                                                TNODE *concrete,
                                                TYPETAB *generic_types,
                                                cexception_t *ex )
{
    if( generic_types &&
        (abstract->params.kind == TK_PLACEHOLDER ||
         abstract->params.kind == TK_NOMINAL)) {
        TNODE *volatile placeholder_implementation =
            typetab_lookup( generic_types, abstract->name );

        if( !placeholder_implementation ) {
            TNODE *volatile shared_concrete = share_tnode( concrete );
            cexception_t inner;
            cexception_guard( inner ) {
                placeholder_implementation =
                    new_tnode_placeholder( abstract->name, &inner );
                tnode_insert_base_type( placeholder_implementation,
                                        &shared_concrete );
                placeholder_implementation =
                    typetab_insert( generic_types, abstract->name,
                                    &placeholder_implementation, &inner );
            }
            cexception_catch {
                delete_tnode( shared_concrete );
                delete_tnode( placeholder_implementation );
                cexception_reraise( inner, ex );
            }
        }
        return placeholder_implementation;
    }
    return abstract;
}

static int tnode_function_arguments_match_msg( TNODE *f1, TNODE *f2,
                                               TYPETAB *generic_types,
                                               int (*check_argument_types)
                                               ( TNODE *f1_arg_type,
                                                 TNODE *f2_arg_type,
                                                 TYPETAB *generic_types,
                                                 cexception_t *ex ),
					       char *msg, int msglen,
                                               cexception_t *ex )
{
    DNODE *f1_arg, *f2_arg;
    int narg = 0;

    assert( f1 );
    assert( f2 );
    f1_arg = tnode_arg_next( f1, NULL );
    f2_arg = tnode_arg_next( f2, NULL );
    while( f1_arg && f2_arg ) {
	TNODE *f1_arg_type = dnode_type( f1_arg );
	TNODE *f2_arg_type = dnode_type( f2_arg );
        int arguments_are_compatible;

        if( f1_arg_type &&
            (f1_arg_type->params.kind == TK_PLACEHOLDER ||
             f1_arg_type->params.kind == TK_NOMINAL)) {
            f1_arg_type =
                tnode_placeholder_implementation( f1_arg_type, f2_arg_type,
                                                  generic_types, ex );
        }

	narg++;

        if( narg == 1 &&
            (f2_arg_type->base_type == f1_arg_type ||
             (f1_arg_type->params.kind == TK_CLASS && f2_arg_type->params.kind == TK_CLASS &&
              (!f1_arg_type->name || !f2_arg_type->name))) &&
            (f1->params.kind == TK_METHOD || f1->params.kind == TK_CONSTRUCTOR ||
             f1->params.kind == TK_DESTRUCTOR) &&
             f1->params.kind == f2->params.kind ) {
            arguments_are_compatible = tnode_types_are_compatible
                ( f1_arg_type, f2_arg_type, generic_types, ex );
        } else {
            arguments_are_compatible = (*check_argument_types)
                ( f1_arg_type, f2_arg_type, generic_types, ex );
        }
             
	if( !arguments_are_compatible ) {
	    if( msg ) {
                if( f1_arg_type && f2_arg_type ) {
                    char *name1 = tnode_name( f1_arg_type );
                    char *name2 = tnode_name( f2_arg_type );
                    if( !name1 && !name2 ) {
                        snprintf( msg, msglen, "old prototype argument %d has "
                                  "different anonymous type", narg );
                    } else
                    if( !name1 ) {
                        snprintf( msg, msglen, "old prototype argument %d has "
                                  "anonymous type, but new prototype has "
                                  "type '%s'", narg, name2 );
                    } else
                    if( !name2 ) {
                        snprintf( msg, msglen, "old prototype argument %d has "
                                  "type '%s', but new prototype has anonymous "
                                  "type", narg, name1 );
                    } else {
                        snprintf( msg, msglen, "old prototype argument %d has "
                                  "type '%s', but new prototype has type '%s'", narg,
                                  name1, name2 );
                    }
                } else {
                    snprintf( msg, msglen, "old or new prototype has undefined "
                              "argument %d", narg );
                }
            }
	    return 0;
	}
	f1_arg = tnode_arg_next( f1, f1_arg );
	f2_arg = tnode_arg_next( f2, f2_arg );
    }
    if( f1_arg || f2_arg ) {
	if( msg ) {
	    snprintf( msg, msglen, "new prototype has too %s arguments",
		      f2_arg ? "many" : "little" );
	}
	return 0;
    }
    return 1;
}

static int tnode_retval_nr( TNODE *tnode )
{
    if( tnode->return_vals == NULL ) return 0;
    else return dnode_list_length( tnode->return_vals );
}

static int tnode_function_retvals_match_msg( TNODE *f1, TNODE *f2,
                                             TYPETAB *generic_types,
					     char *msg, int msglen,
					     cexception_t *ex )
{
    DNODE *f1_retval, *f2_retval;
    int nretval = 0;

    assert( f1 );
    assert( f2 );

    f1_retval = tnode_retval_next( f1, NULL );
    f2_retval = tnode_retval_next( f2, NULL );
    while( f1_retval && f2_retval ) {
	TNODE *f1_retval_type = dnode_type( f1_retval );
	TNODE *f2_retval_type = dnode_type( f2_retval );
	char pad[20];

	nretval++;
	if( !tnode_types_are_identical( f1_retval_type, f2_retval_type,
					generic_types, ex )) {
	    if( msg ) {
		int retval_count1 = tnode_retval_nr( f1 );
		int retval_count2 = tnode_retval_nr( f2 );
		int retval_count = retval_count1 > retval_count2 ?
		    retval_count1 : retval_count2;

		snprintf( pad, sizeof(pad), " %d", nretval );
                if( f1_retval_type && f2_retval_type ) {
                    snprintf( msg, msglen, "old prototype return value%s has "
                              "type %s, but new prototype has type %s",
                              (retval_count < 2 ? "" : pad),
                              tnode_name( f1_retval_type ),
                              tnode_name( f2_retval_type ));
                } else {
                    snprintf( msg, msglen, "old or new prototype undefined "
                              "return values" );
                }
	    }
	    return 0;
	}
	f1_retval = tnode_retval_next( f1, f1_retval );
	f2_retval = tnode_retval_next( f2, f2_retval );
    }
    if( f1_retval || f2_retval ) {
	if( msg ) {
	    snprintf( msg, msglen, "new prototype has too %s return values",
		      f2_retval ? "many" : "little" );
	}
	return 0;
    }
    return 1;
}

static int tnode_generic_function_prototypes_match( TNODE *f1, TNODE *f2,
                                                    TYPETAB *generic_types,
                                                    char *msg, int msglen,
                                                    cexception_t *ex )
{
    return
	tnode_function_arguments_match_msg( f1, f2, generic_types,
                                            tnode_types_are_identical,
                                            msg, msglen, ex ) &&
	tnode_function_retvals_match_msg( f1, f2, generic_types, msg, msglen, ex );
}

static int
tnode_generic_functions_are_assignment_compatible( TNODE *f1, TNODE *f2,
                                                   TYPETAB *generic_types,
                                                   char *msg, int msglen,
                                                   cexception_t *ex )
{
    return
	tnode_function_arguments_match_msg( f1, f2, generic_types,
                                            tnode_types_are_contravariant,
                                            msg, msglen, ex ) &&
	tnode_function_retvals_match_msg( f1, f2, generic_types, msg, msglen, ex );
}

int tnode_function_prototypes_match_msg( TNODE *f1, TNODE *f2,
					 char *msg, int msglen )
{
    return 
        tnode_generic_function_prototypes_match( f1, f2,
                                                 NULL, /* generic_types, */
                                                 msg, msglen,
                                                 NULL /* cexception_t *ex */ );
}

int tnode_function_prototypes_match( TNODE *f1, TNODE *f2 )
{
    return tnode_function_prototypes_match_msg( f1, f2, NULL, 0 );
}

TLIST *new_tlist_with_concrete_types( TLIST *tlist_with_generics,
                                      TYPETAB *generic_table,
                                      int *has_generics,
                                      cexception_t *ex )
{
    TLIST *volatile ret = NULL;
    TLIST *volatile next = NULL;
    TNODE *volatile shared_tnode = NULL;
    cexception_t inner;

    if( !tlist_with_generics ) {
        return NULL;
    }
    
    cexception_guard( inner ) {
        TNODE *tnode = tlist_data( tlist_with_generics );
        next = new_tlist_with_concrete_types
            (
             tlist_next( tlist_with_generics ),
             generic_table, has_generics, &inner
            );

        if( tnode_has_generic_type( tnode )) {
            shared_tnode = new_tnode_with_concrete_types
                ( tnode, generic_table, has_generics, &inner );
        } else {
            shared_tnode = share_tnode( tnode );
        }
        create_tlist( &ret, &shared_tnode, next, &inner );
        next = NULL;
    }
    cexception_catch {
        delete_tlist( ret );
        delete_tlist( next );
        delete_tnode( shared_tnode );
        cexception_reraise( inner, ex );
    }

    return ret;
}

/*
  The 'new_tnode_with_concrete_types' creates a new TNODE that
  describes a type with all generic types specified in the
  'generic_table' recursively replaced with the concrete
  implementations from the same table. Intended to compile statements
  like:

  var b : A with ( T => string ); // here A is a structure with the fields
                                  // of generic type T.
*/

TNODE *new_tnode_with_concrete_types( TNODE *tnode_with_generics,
                                      TYPETAB *generic_table,
                                      int *has_generics,
                                      cexception_t *ex )
{
    assert( has_generics != NULL );
    assert( generic_table );

    if( !tnode_with_generics ) {
        return NULL;
    }
    
    if( !tnode_has_generic_type( tnode_with_generics )) {
        *has_generics = 0;
        return share_tnode( tnode_with_generics );
    } else {
        if( tnode_kind( tnode_with_generics ) == TK_GENERIC ||
            tnode_kind( tnode_with_generics ) == TK_PLACEHOLDER ||
            tnode_kind( tnode_with_generics ) == TK_NOMINAL ) {
            TNODE *tnode_implementation =
                typetab_lookup_paired_type( generic_table,
                                            tnode_with_generics );
            if( tnode_implementation != NULL ) {
                *has_generics = 0;
                return share_tnode( tnode_implementation );
            } else {
                *has_generics = 1;
                return share_tnode( tnode_with_generics );
            }
        } else {
            TNODE *existing_implementation =
                typetab_lookup_paired_type( generic_table,
                                            tnode_with_generics );

            TNODE *volatile concrete_tnode = NULL;
            
            if( existing_implementation ) {
                concrete_tnode = share_tnode( existing_implementation );
            } else {
                concrete_tnode = new_tnode( ex );
                TNODE *volatile type_pair = NULL;
                TNODE *volatile shared_concrete_tnode =
                    share_tnode( concrete_tnode );
                TNODE *volatile shared_generic_tnode =
                    share_tnode( tnode_with_generics );
                cexception_t inner;

                if( tnode_is_reference( tnode_with_generics )) {
                    tnode_set_flags( concrete_tnode, TF_IS_REF );
                }

                concrete_tnode->params = tnode_with_generics->params;
                
                if( concrete_tnode->params.kind == TK_DERIVED ) {
                    tnode_set_flags( concrete_tnode, TF_IS_EQUIVALENT );
                }
                
                cexception_guard( inner ) {

                    // Interface names are inherited:
                    if( tnode_kind( tnode_with_generics ) == TK_INTERFACE ) {
                        tnode_set_name( concrete_tnode,
                                        tnode_name( tnode_with_generics ),
                                        &inner);
                    }
                    
                    type_pair = new_tnode_type_pair
                        ( &shared_generic_tnode, &shared_concrete_tnode,
                          &inner );

                    typetab_insert( generic_table,
                                    tnode_name( tnode_with_generics ),
                                    &type_pair, &inner );
                
                    concrete_tnode->base_type = new_tnode_with_concrete_types
                        ( tnode_with_generics->base_type,
                          generic_table, has_generics, &inner );

                    concrete_tnode->element_type = new_tnode_with_concrete_types
                        ( tnode_with_generics->element_type,
                          generic_table, has_generics, &inner );

                    concrete_tnode->interfaces = new_tlist_with_concrete_types
                        ( tnode_with_generics->interfaces, generic_table,
                          has_generics, &inner );
                
                    concrete_tnode->fields = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->fields, generic_table,
                          has_generics, &inner );

                    concrete_tnode->operators = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->operators, generic_table,
                          has_generics, &inner );

                    concrete_tnode->conversions = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->conversions, generic_table,
                          has_generics, &inner );

                    concrete_tnode->methods = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->methods, generic_table,
                          has_generics, &inner );

                    concrete_tnode->args = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->args, generic_table,
                          has_generics, &inner );

                    concrete_tnode->return_vals = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->return_vals, generic_table,
                          has_generics, &inner );

                    concrete_tnode->constructor = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->constructor, generic_table,
                          has_generics, &inner );

                    concrete_tnode->destructor = new_dnode_list_with_concrete_types
                        ( tnode_with_generics->destructor, generic_table,
                          has_generics, &inner );

                }
                cexception_catch {
                    delete_tnode( type_pair );
                    delete_tnode( shared_concrete_tnode );
                    delete_tnode( shared_generic_tnode );
                    delete_tnode( concrete_tnode );
                    cexception_reraise( inner, ex );
                }
            
                if( *has_generics ) {
                    tnode_set_has_generics( concrete_tnode );
                }
                delete_tnode( type_pair );
                delete_tnode( shared_concrete_tnode );
                delete_tnode( shared_generic_tnode );
            }
            
            return concrete_tnode;
        }
    }
}
