/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __SYMTAB_H
#define __SYMTAB_H

/* symbol table to store defined variables */

typedef struct SYMTAB SYMTAB; /* variable symbol table */

#include <vartab.h>
#include <typetab.h>
#include <cexceptions.h>

SYMTAB *new_symtab( VARTAB *vartab,
		    VARTAB *consts,
		    TYPETAB *typetab,
		    VARTAB *operators,
		    cexception_t *ex );

void delete_symtab( SYMTAB *table );

void obtain_tables_from_symtab( SYMTAB *symtab,
				VARTAB **vartab,
				VARTAB **consts,
				TYPETAB **typetab,
				VARTAB **operators );

TYPETAB *symtab_typetab( SYMTAB *st );
VARTAB *symtab_vartab( SYMTAB *st );
VARTAB *symtab_consttab( SYMTAB *st );
VARTAB *symtab_optab( SYMTAB *st );

#endif
