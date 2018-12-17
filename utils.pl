:- import reverse/2, length/2, ith/3 from basics.

getIthColumn([],_,[]).
getIthColumn([H|T],I,[IthElement|Rest]) :-
	ith(I,H,IthElement),
	getIthColumn(T,I,Rest).

getColumnsHelper(_,0,[]).
getColumnsHelper(InMatrix,N,[Column|Rest]) :-
	N > 0,
	getIthColumn(InMatrix,N,Column),
	N1 is N - 1,
	getColumnsHelper(InMatrix,N1,Rest).	

getColumns(InMatrix, OutMatrix) :-
	length(InMatrix, InMatrixLength),
	getColumnsHelper(InMatrix, InMatrixLength, OutMatrixReversed),
	reverse(OutMatrixReversed, OutMatrix).

reverseMatrixElements([],[]).
reverseMatrixElements([H|T], [ReversedElement|Rest]) :-
	reverse(H,ReversedElement),
	reverseMatrixElements(T,Rest).

getFirstNElements([],_,[]).
getFirstNElements(_,0,[]).
getFirstNElements([H|T],N,[H|Rest]) :-
	N > 0,
	N1 is N -1,
	getFirstNElements(T,N1,Rest).
