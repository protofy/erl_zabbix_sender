REBAR=`which rebar || ./rebar`
all: compile docs
update: get-deps update-deps
full: clean get-deps update-deps compile docs tests
ci: get-deps update-deps compile docs tests
prod: get-deps update-deps compile-prod test docs

get-deps:
	@$(REBAR) get-deps
update-deps:
	@$(REBAR) update-deps
compile:
	@$(REBAR) compile
compile-prod:
	@$(REBAR) compile 
tests:
	@$(REBAR) skip_deps=true eunit
clean:
	@$(REBAR) skip_deps=true clean
clean-all:
	@$(REBAR) clean
docs:
	@$(REBAR) skip_deps=true doc
