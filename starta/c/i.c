#include <stdio.h>
#include <math.h>

int image[] = {
#include "image.ci"
};


int
main()
{
    long length = sizeof(image)/sizeof(image[0]);

    printf( "%ld data points\n", length );

    double sum, mean, variance, diff, sd;
    int i;

    sum = 0.0;
    for( i = 0; i < length; i ++ ) {
        sum += image[i];
    }

    mean = sum/length;

    printf( "mean = %.10g\n", mean );

    sum = 0.0;
    for( i = 0; i < length; i ++ ) {
        diff = mean - image[i];
        sum += diff * diff;
    }

    variance = sum / ( length - 1 );

    printf( "sample variance     : %.10g\n", sum/length );
    printf( "population variance : %.10g\n", variance );

    printf( "sample sd     : %.10g\n", sqrt(sum/length) );
    printf( "population sd : %.10g\n", sqrt(variance) );

    return 0;
}
