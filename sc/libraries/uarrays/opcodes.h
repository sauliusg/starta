/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __OPCODES_H
#define __OPCODES_H

#include <run.h>

#if 0
#define INSTRUCTION_FN_ARGS instruction_t *code, cexception_t *ex
#else
#define INSTRUCTION_FN_ARGS void
#endif

extern istate_t *istate_ptr;

int ARRAY_UB2I( INSTRUCTION_FN_ARGS );
int ARRAY_US2I( INSTRUCTION_FN_ARGS );

#endif
