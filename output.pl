chosenNote("cccchosenNote(").

writeNote(P,T,N) :-
	write("chosenNote("),
	write(P),
	write(","),
	write(T),
	write(","),
	write(N),
	write(") ").

test(P) :-
	write(chosenNote).
