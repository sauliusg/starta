/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __BYTEORDER_H
#define __BYTEORDER_H

typedef enum {
  BO_UNKNOWN_ENDIAN = 0,
  BO_BIG_ENDIAN,
  BO_LITTLE_ENDIAN,
  BO_MIXED_ENDIAN,
  BO_MACHINE_ENDIAN,
  last_byteorder
} byteorder_t;

#ifdef USE_LITTLE_ENDIAN
#define DEFAULT_BYTEORDER BO_LITTLE_ENDIAN
#else
#define DEFAULT_BYTEORDER BO_BIG_ENDIAN
#endif

#endif
