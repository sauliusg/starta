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

int pack_value( stackcell_t *stack_cell, char typechar, ssize_t size,
                ssize_t *offset, byte *blob,
                int (*pack)( stackcell_t *stack_cell, char typechar,
                             ssize_t size, ssize_t *offset, byte *blob ),
                cexception_t *ex
                );

int pack_array_values( byte *blob, stackcell_t *array,
                       char *description, ssize_t *offset,
                       int (*pack)( stackcell_t *stack_cell, 
                                    char typechar, ssize_t size, 
                                    ssize_t *offset, byte *blob ),
                       cexception_t *ex );

int pack_array_layer( byte *blob, stackcell_t *array, char *description,
                      ssize_t *offset, ssize_t level,
                      int (*pack)( stackcell_t *stack_cell, 
                                   char typechar, ssize_t size, 
                                   ssize_t *offset, byte *blob ),
                      cexception_t *ex  );

int unpack_value( stackcell_t *stack_cell, char typechar, ssize_t size,
                  ssize_t *offset, byte *blob,
                  int (*unpack)( stackcell_t *stack_cell, char typechar,
                                 ssize_t size, ssize_t *offset, byte *blob,
                                 cexception_t *ex ),
                  cexception_t *ex );

int unpack_array_values( byte *blob, stackcell_t *array,
                         char *description, ssize_t *offset,
                         int (*unpack)( stackcell_t *stack_cell, 
                                        char typechar, ssize_t size,
                                        ssize_t *offset, byte *blob,
                                        cexception_t *ex ),
                         cexception_t *ex );

void *unpack_array_layer( byte *blob, stackcell_t *array, char *description,
                          ssize_t *offset, ssize_t level,
                          int (*unpack)( stackcell_t *stack_cell, 
                                         char typechar, ssize_t size,
                                         ssize_t *offset, byte *blob,
                                         cexception_t *ex  ),
                          cexception_t *ex  );

#endif
