/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __STACKCELL_H
#define __STACKCELL_H

#include <stdlib.h>
#include <typesize.h>

union stackunion {
  unsigned char c;
  signed char b;
  short s;
  int i;
  long l;
  llong ll;
  void *ptr;
  float f;
  double d;
  ldouble ld;
  ssize_t offs;
  ssize_t ssize;
};

/* For now, 'ptr' must be the *second* field, at the bottom of the
   stackcell structure. This is because some bytecode operators
   (e.g. INDEX) will assume that taking address of a stackcell gives
   address of any numeric variable stored in that stackcell. */

typedef struct stackcell {
    union stackunion num;
    void *ptr;
} stackcell_t;

#define STACK_CELLS(N) \
    ( (N)/sizeof(union stackunion) + \
    ( (N)%sizeof(union stackunion) == 0 ? 0 : 1 ) )

#if 1
#define USE_POINTER_SEGREGATION 1
#define USE_OFFSETTED_POINTERS  1
#else
#define USE_POINTER_SEGREGATION 0
#define USE_OFFSETTED_POINTERS  0
#endif

#if USE_POINTER_SEGREGATION
#define PTR ptr
#else
#define PTR num.ptr
#endif

#if USE_OFFSETTED_POINTERS

#define STACKCELL_PTR( s )            ((s).PTR + (s).num.offs)

#define STACKCELL_SET_PTR( s, p, o )  ((s).PTR = (p), (s).num.offs = (o))
#define STACKCELL_SET_ADDR( s, p )    ((s).PTR = (p), (s).num.offs = 0)
#define STACKCELL_MOVE_PTR( s1, s2 )  ((s1).PTR = (s2).PTR, (s1).num.offs = (s2).num.offs)
#define STACKCELL_OFFSET_PTR( s, o )  ((s).num.offs += (o))
#define STACKCELL_ZERO_PTR( s )       ((s).PTR = (NULL))

#else

#define STACKCELL_PTR( s )            (s).PTR

#define STACKCELL_SET_PTR( s, p, o )  (s).PTR = ((char*)p) + o
#define STACKCELL_SET_ADDR( s, p )    (s).PTR = p
#define STACKCELL_MOVE_PTR( s1, s2 )  (s1).PTR = (s2).PTR
#define STACKCELL_OFFSET_PTR( s, o )  ((s).PTR) += o
#define STACKCELL_ZERO_PTR( s )

#endif

#endif
