pbidl:pbidl.y
	goyacc -o pbidl.go -p Pb $< && go build -o $@
	rm -f y.output pbidl.go

clean:
	-rm handler.go pbidl
