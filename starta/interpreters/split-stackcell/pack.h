/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __PACK_H
#define __PACK_H

#include <stdlib.h>
#include <stackcell.h>
#include <cexceptions.h>

int pack_value( void *value, char typechar, ssize_t size,
                ssize_t *offset, byte *blob,
                int (*pack)( void *value, char typechar,
                             ssize_t size, ssize_t *offset, byte *blob ),
                cexception_t *ex
                );

int pack_array_values( byte *blob, void **array,
                       char *description, ssize_t *offset,
                       int (*pack)( void *value, 
                                    char typechar, ssize_t size, 
                                    ssize_t *offset, byte *blob ),
                       cexception_t *ex );

int pack_array_layer( byte *blob, void **array, char *description,
                      ssize_t *offset, ssize_t level,
                      int (*pack)( void *value, 
                                   char typechar, ssize_t size, 
                                   ssize_t *offset, byte *blob ),
                      cexception_t *ex  );

int unpack_value( void *value, char typechar, ssize_t size,
                  ssize_t *offset, byte *blob,
                  int (*unpack)( void *value, char typechar,
                                 ssize_t size, ssize_t *offset, byte *blob,
                                 cexception_t *ex ),
                  cexception_t *ex );

int unpack_array_values( byte *blob, void **array,
                         int element_nref,
                         char *description, ssize_t *offset,
                         int (*unpack)( void *value,
                                        char typechar, ssize_t size,
                                        ssize_t *offset, byte *blob,
                                        cexception_t *ex ),
                         cexception_t *ex );

void *unpack_array_layer( byte *blob, void **array,
                          int element_nref,
                          char *description, ssize_t *offset, ssize_t level,
                          int (*unpack)( void *value, 
                                         char typechar, ssize_t size,
                                         ssize_t *offset, byte *blob,
                                         cexception_t *ex  ),
                          cexception_t *ex  );

#endif
