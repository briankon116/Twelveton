:- include(composition).

validate(ToneRow, Length, Composition) :-	
	tell(antonOutput),
	compose(ToneRow, Length, Composition) ->
	tell(antonOutput),
	write(yes),
	told
	;
	write(no),
	told.
