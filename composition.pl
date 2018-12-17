:- import member/2, flatten/2 from basics.
:- import random/3 from random.
:- include(twelveToneMatrix).

createComposition(_,0,[]).
createComposition(M,N,[ChosenRow|Rest]) :-
	N > 0,
	length(M,L),
	L1 is L + 1,
	random(1,L1,I),	
	ith(I,M,ChosenRow),
	N1 is N - 1,
	createComposition(M,N1,Rest).	

compose(L,N,C) :-
	createTwelveToneMatrix(L,M),
	length(L,ToneRowLength),
	NumberOfRows is (N // ToneRowLength + 1),
	createComposition(M,NumberOfRows,C1),
	flatten(C1,C2),
	getFirstNElements(C2,N,C),
	tell(antonOutput),
	write(C),
	told.
