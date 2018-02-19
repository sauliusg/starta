/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TNODE_COMPAT_H
#define __TNODE_COMPAT_H

#include <tnode.h>
#include <typetab.h>
#include <cexceptions.h>

int tnode_types_are_compatible( TNODE *t1, TNODE *t2,
				TYPETAB *generic_types,
				cexception_t *ex );

int tnode_types_are_assignment_compatible( TNODE *t1, TNODE *t2,
                                           TYPETAB *generic_types,
                                           char *msg, ssize_t msglen,
                                           cexception_t *ex );

int tnode_types_are_identical( TNODE *t1, TNODE *t2,
			       TYPETAB *generic_types,
			       cexception_t *ex );

#endif
