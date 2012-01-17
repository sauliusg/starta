/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* An object to store all symbol tables of a compiler (variables,
   constants, types). */

/* exports: */
#include <symtab.h>

/* uses: */
#include <vartab.h>
#include <typetab.h>
#include <allocx.h>
#include <assert.h>

struct SYMTAB {
    VARTAB *vartab;   /* declared variables, with scopes */
    VARTAB *consts;   /* declared constants, with scopes */
    TYPETAB *typetab; /* declared types and their scopes */
};

SYMTAB *new_symtab( VARTAB *vartab,
		    VARTAB *consts,
		    TYPETAB *typetab,
		    cexception_t *ex )
{
    SYMTAB *symtab = callocx( sizeof(SYMTAB), 1, ex );

    symtab->vartab = vartab;
    symtab->consts = consts;
    symtab->typetab = typetab;

    return symtab;
}

void delete_symtab( SYMTAB *table )
{
    if( !table ) return;
    delete_vartab( table->vartab );
    delete_vartab( table->consts );
    delete_typetab( table->typetab );
    freex( table );
}

void obtain_tables_from_symtab( SYMTAB *symtab,
				VARTAB **vartab,
				VARTAB **consts,
				TYPETAB **typetab )
{
    assert( symtab );
    assert( vartab );
    assert( consts );
    assert( typetab );

    *vartab = symtab->vartab;
    *consts = symtab->consts;
    *typetab = symtab->typetab;

    symtab->vartab = NULL;
    symtab->consts = NULL;
    symtab->typetab = NULL;
}
