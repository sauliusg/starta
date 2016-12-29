//--*- C -*------------------------------------------------------------------*\
//$Author: saulius $
//$Date: 2015-11-27 19:52:46 +0200 (Fri, 27 Nov 2015) $ 
//$Revision: 80 $
//$URL: svn+ssh://saulius-grazulis.lt/home/saulius/svn-repositories/sgem-xray/trunk/lib/MatInvGJ.inc $
//---------------------------------------------------------------------------*/
//*
// Matrix inversion using Gauss-Jordan elimination with partial pivoting.
// https://en.wikipedia.org/wiki/Gaussian_elimination
//**

// In future, this file will be included after the definition of the
// 'melement' type, e.g.:

// use * from std;
// 
// type melement = float;
// 
// include "MatInv.inc" ;

use * from CheckMat;
use * from MatAlg( melement );

function abs( x : melement ): melement { return x > 0 melement ? x : -x }

function pivot( m : array [][] of melement; k : long ): long
{
    var maxi = k;
    for var j = k+1L to llast(m) do
        if( abs(m[maxi][k]) < abs(m[j][k]) ) {
            maxi = j
        }
    enddo

    return maxi;
}

procedure vdiv( v : array of melement; k : melement )
{
    for var e in v do
        e /= k;
    enddo
}

procedure vksub( v1, v2 : array of melement; k : melement )
{
    for var i = 0L to llast(v1) do
        v1[i] -= k * v2[i];
    enddo
}

procedure invert( m : array [][] of melement ): melement[][]
{
    assert is_square( m );

    var N = llength( m );

    pragma long;

    var a = new melement[N][N*2];

    for( var i = 0; i < N; i ++ ) {
        a[i] := m[i];
        a[i][N+i] = 1 melement;
    }

    // . a;

    // Elemination:

    for( var k = 0; k < N-1; k++ ) {
        var j = pivot( a, k );
        // . "pivot = ", a[j][k], a[j];
        if( k != j ) {
            a[k], a[j] = a[j], a[k];
        }
        // . a;
        vdiv( a[k], a[k][k] );
        // . a;
        for( var l = k+1; l < N; l++ ) {
            vksub( a[l], a[k], a[l][k] )
        }
        // . a;
    }

    vdiv( a[N-1], a[N-1][N-1] );

    for( var k = N-1; k > 0; k-- ) {
        // . a;
        for( var l = k-1; l >= 0; l-- ) {
            vksub( a[l], a[k], a[l][k] )
        }
        // . a;
    }

    for( var i = 0; i < N; i ++ ) {
        m[i] := a[i][N..-1];
    }

    return m;
}

function inverted( m : array [][] of melement ): melement[][]
{
    return invert( clone( m, 2 ));
}
