//--*- C -*------------------------------------------------------------------*\
//$Author: saulius $
//$Date: 2015-08-21 22:26:03 +0300 (Fri, 21 Aug 2015) $ 
//$Revision: 74 $
//$URL: svn+ssh://saulius-grazulis.lt/home/saulius/svn-repositories/sgem-xray/trunk/lib/MatAlg.inc $
//---------------------------------------------------------------------------*/
//*
// Provides simple functions for matrix operator algebra.
//**

// In future, this file will be included after the definition of the
// 'melement' type, e.g.:

// use * from std;
// 
// type melement = float;
// 
// include "MatAlg.inc" ;

use * from CheckMat;

// Return a identity matrix N x N:
function identity( int N ) : melement[][]
{
    var identity_matrix = new melement[N][N];

    for( var i = 0; i < N; i ++ ) {
        identity_matrix[i][i] = 1 melement;
    }

    return identity_matrix;
}

// Return a matrix N x N, initialised with 0:
function matrix( int N; int M = 0 ) : melement[][]
{
    if M == 0 then M = N endif;
    return new melement[N][M]
}

function multiply( m1, m2 : array [][] of melement): array [][] of melement
{
    assert is_rectangular( m1 );
    assert is_rectangular( m2 );
    assert length(m1) > 0;
    assert length(m1[0]) == length(m2);

    var prod = new melement[length(m1)][length(m2[0])];

    for( var i = 0; i < length(m1); i ++ ) {
        for( var j = 0; j < length(m2[0]); j ++ ) {
            prod[i][j] = 0 melement;
            for( var k = 0; k < length(m2); k ++ ) {
                prod[i][j] += m1[i][k] * m2[k][j];
            }
        }
    }
    return prod;
}

operator "*"( m1, m2 : array [][] of melement ): array [][] of melement
{
    return multiply( m1, m2 );
}

function mtimes( melement k; m : array [][] of melement): array [][] of melement
{
    var prod = clone( m, 2 );

    for( var i = 0; i < length(m); i ++ ) {
        for( var j = 0; j < length(m[i]); j ++ ) {
            prod[i][j] *= k;
        }
    }
    return prod;
}

function det3( s : melement[][] ): melement
{
    return
        + s[0][0] * s[1][1] * s[2][2]
        + s[1][0] * s[2][1] * s[0][2]
        + s[0][1] * s[1][2] * s[2][0]

        - s[0][2] * s[1][1] * s[2][0]
        - s[0][0] * s[1][2] * s[2][1]
        - s[0][1] * s[1][0] * s[2][2];
}

function det2( s : melement[][] ): melement
{
    return
        + s[0][0] * s[1][1]
        - s[1][0] * s[0][1]
}

exception UNSUPPORTED_MATRIX_SIZE;

function adjunct3( m : melement[][]; int row; int col ): melement
{
    var matrix = new melement[2][2];

    var mi, mj = 0, 0;
    for( var i = 0; i < 3; i ++ ) {
        do continue if( i == row );
        mj = 0;
        for( var j = 0; j < 3; j ++ ) {
	    do continue if( j == col );
            matrix[mi][mj] = m[i][j];
            mj ++;
        }
        mi ++;
    }
    do raise UNSUPPORTED_MATRIX_SIZE("Adjunct size is not 2 in 'adjunct3()'")
           if( mi != 2 );
    do raise UNSUPPORTED_MATRIX_SIZE("Adjunct size is not 2 in 'adjunct3()'")
           if( mj != 2 );
    var coef = ((row + col) % 2 == 0) ? +1 melement: -1 melement;
    return coef * det2( matrix );
}

exception NON_INVERTIBLE;

function inv3( m : melement[][] ): melement[][]
{
    var det = det3( m );

    // Check whether we can invert 'det' over the field of type
    // 'melement':
    var inverse = 1 melement/det;
    var diff = 1 melement - inverse * det;
    var abs = diff > 0 melement ? diff : -diff;
    if( abs > 0.9 melement ) {
        raise NON_INVERTIBLE( "can not invert matrix with given elements" );
    }
    return mtimes( inverse, 
                   [
                    [ adjunct3(m,0,0), adjunct3(m,1,0), adjunct3(m,2,0) ],
                    [ adjunct3(m,0,1), adjunct3(m,1,1), adjunct3(m,2,1) ],
                    [ adjunct3(m,0,2), adjunct3(m,1,2), adjunct3(m,2,2) ]
                   ]
                 )
}

operator "." ( m : melement[][] )
{
    . "[";
    for( var i = 0; i < length(m); i ++ ) {
        < " [";
        for( var j = 0; j < length(m[i]); j ++ ) {
            < "", m[i][j];
        }
        . " ]";
    }
    . "]";
}

operator "<" ( v : melement[] )
{
    < "[";
    for( var i = 0; i < length(v); i ++ ) {
        < "", v[i];
    }
    < "]";
}

operator "." ( v : melement[] ) { < v }
