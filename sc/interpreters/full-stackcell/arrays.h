/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* Macros for different array implementations in the runtime system of
   the compiler: */

#ifndef __ARRAYS_H
#define __ARRAYS_H

#define ARRAY_ELEMENT(a) ((a).num.I)

#define GET_ARRAY_ELEMENT(a,i) ((a)[i].num.I)
#define SET_ARRAY_ELEMENT(a,i,v) (a)[i].num.I = (v)

#endif
