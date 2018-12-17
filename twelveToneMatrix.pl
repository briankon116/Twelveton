:- import append/3 from basics.
:- include(utils).

% Invert a note
inversion(N1, N2) :-
	N2 is 12 - N1.

% Given a note from the tone row and a note from the inversion column, transpose the note to the new inversion's key
transpose(N1, N2, N3) :-
	R is N1 + N2,
	R >= 12,
	N3 is R - 12.
transpose(N1, N2, N3) :-
	R is N1 + N2,
	R < 12,
	N3 is R.

% Given a note from the tone row, create a row of that note's inversion
createInversionRow([],_,[]).
createInversionRow([H|T],N,[N1|L1]) :-
	transpose(N,H,N1),
	createInversionRow(T,N,L1).

% Create the twelve tone matrix from the input tone row
createTwelveToneMatrixHelper([],_,[]).
createTwelveToneMatrixHelper([H|T],L,[[N|L1]|M1]) :-
	inversion(H, N),
	createInversionRow(L, N, L1),
	createTwelveToneMatrixHelper(T,L,M1).

% Turn the input tone row, create matrix and generate all options on how to use the matrix
createTwelveToneMatrix([H|T], M) :-
	createTwelveToneMatrixHelper(T, T, M1),
	getColumns([[H|T]|M1], M2),
	append([[H|T]|M1],M2, M3),
	reverseMatrixElements(M3, M4),
	append(M3,M4,M).
