%% ====================================================================
%%
%% Copyright (c) Protofy GmbH & Co. KG, Kaiser-Wilhelm-Straße 85, 20355 Hamburg/Germany and individual contributors.
%% All rights reserved.
%% 
%% Redistribution and use in source and binary forms, with or without modification,
%% are permitted provided that the following conditions are met:
%% 
%%     1. Redistributions of source code must retain the above copyright notice,
%%        this list of conditions and the following disclaimer.
%% 
%%     2. Redistributions in binary form must reproduce the above copyright
%%        notice, this list of conditions and the following disclaimer in the
%%        documentation and/or other materials provided with the distribution.
%% 
%%     3. Neither the name of Protofy GmbH & Co. KG nor the names of its contributors may be used
%%        to endorse or promote products derived from this software without
%%        specific prior written permission.
%% 
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
%% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
%% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
%% ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
%% ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
%% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%
%% ====================================================================
%%
%% @author Bjoern Kortuemm (@uuid0) <bjoern@protofy.com>

-module(zabbix_sender_tests).

-export([]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("protofy_common/include/protofy_common.hrl").

-define(ETS, zabbix_sender_tests_tab).

-record(state, { cmd_opts, resolve_when, resolve_to, cmd_format, bin, tref, error_handler }).

%% ====================================================================
%% Tests for internal functions
%% ====================================================================

%% Test cmd_format/2
%% ====================================================================
cmd_format_test_() ->
	Bin = "test_bin",
	{setup,
	 fun() ->
			 mock_filelib(),
			 Rest = " -k \"~s\" -o ~p",
			 T = fun(E, X) ->
						 ?_assertEqual(Bin ++ E ++ Rest, zabbix_sender:cmd_format(Bin, X))
						 end,
			 T
	 end,
	 fun(_) ->
			 protofy_test_util:unmock(filelib)
	 end,
	 fun(T) ->
			 [
			  {"simple", T([], [])},
			  {"remote_addr", T(" -z \"1.2.3.4\"", [{remote_addr, "1.2.3.4"}])},
			  [{"remote_port " ++ F, T(" -p \"1234\"", [{remote_port, V}])}
			   || {F, V} <- [{"integer", 1234}, {"binary", <<"1234">>}, {"list", "1234"}]],
			  {"local_name string", T(" -s \"test\"", [{local_name, "test"}])},
			  {"local_name binary", T(" -s \"test\"", [{local_name, <<"test">>}])},
			  {"config file string", T(" -c \"regular\"", [{config_file, "regular"}])},
			  {"config file binary", T(" -c \"regular\"", [{config_file, <<"regular">>}])},
			  {"config file enoent",
			   ?_assertError(enoent, zabbix_sender:cmd_format(Bin, [{config_file, "any"}]))}
			 ]
	 end}.


%% Test cmd/3
%% ====================================================================
cmd_test_() ->
	[
	 {"string string integer", ?_assertEqual("{key,42}", zabbix_sender:cmd("{~s,~B}", "key", 42))},
	 {"binary string integer", ?_assertEqual("{key,42}", zabbix_sender:cmd(<<"{~s,~B}">>, "key", 42))},
	 {"string binary integer", ?_assertEqual("{key,42}", zabbix_sender:cmd("{~s,~B}", <<"key">>, 42))},
	 {"binary binary integer", ?_assertEqual("{key,42}", zabbix_sender:cmd(<<"{~s,~B}">>, <<"key">>, 42))}
	].


%% Test do_info/1
%% ====================================================================
do_info_test_() ->
	A = zabbix_sender:do_info(#state{bin="TestBin",
									 resolve_when=on_call,
									 resolve_to=inet6,
									 cmd_opts=[{some_opt, 1}]}),
	[
	 {"resolve_when", ?_assertEqual(on_call, ?GV(resolve_when, A))},
	 {"resolve_to", ?_assertEqual(inet6, ?GV(resolve_to, A))},
	 {"zabbix_sender_bin", ?_assertEqual("TestBin", ?GV(zabbix_sender_bin, A))},
	 {"some_opt", ?_assertEqual(1, ?GV(some_opt, A))}
	].


%% Test resolve_when/1
%% ====================================================================
resolve_when_test_() ->
	[
	 {"default", ?_assertEqual(on_change, zabbix_sender:resolve_when(default))},
	 {"on_change", ?_assertEqual(on_change, zabbix_sender:resolve_when(on_change))},
 	 {"on_call", ?_assertEqual(on_call, zabbix_sender:resolve_when(on_call))},
 	 {"on_timer 10", ?_assertEqual({on_timer, 10}, zabbix_sender:resolve_when({on_timer, 10}))}
	].


%% Test resolve_to/1
%% ====================================================================
resolve_to_test_() ->
	[
	 {"default", ?_assertEqual(inet, zabbix_sender:resolve_to(default))},
	 {"inet -> inet", ?_assertEqual(inet, zabbix_sender:resolve_to(inet))},
	 {"ipv4 -> inet", ?_assertEqual(inet, zabbix_sender:resolve_to(ipv4))},
	 {"inet6 -> inet6", ?_assertEqual(inet6, zabbix_sender:resolve_to(inet6))},
	 {"ipv6 -> inet6", ?_assertEqual(inet6, zabbix_sender:resolve_to(ipv6))}
	].


%% Test local_name/1
%% ====================================================================
local_name_test_() ->
	Hostname =	string:strip(os:cmd("hostname -f"), right, $\n),
	[
	 {"default", ?_assertEqual(Hostname, zabbix_sender:local_name(default))},
	 {"auto", ?_assertEqual(Hostname, zabbix_sender:local_name(auto))},
	 {"binary", ?_assertEqual("test", zabbix_sender:local_name(<<"test">>))},
	 {"list", ?_assertEqual("test", zabbix_sender:local_name("test"))},
	 {"error on non-printable", ?_assertException(error, "Invalid Name (must be printable)", zabbix_sender:local_name([1]))}
	].


%% Test remote_addr/3
%% ====================================================================
remote_addr_test_() ->
	[
	 {"binary", ?_assertEqual("localhost", zabbix_sender:remote_addr(<<"localhost">>, false, nothing))},
	 {"list", ?_assertEqual("localhost", zabbix_sender:remote_addr("localhost", false, nothing))},
	 {"resolve inet", ?_assertEqual("127.0.0.1", zabbix_sender:remote_addr("localhost", true, inet))},
	 {"resolve inet6", ?_assertEqual("::1", zabbix_sender:remote_addr("localhost", true, inet6))}
	].


%% Test remote_port/1
%% ====================================================================
remote_port_test_() ->
	[
	 {"default", ?_assertEqual(10051, zabbix_sender:remote_port(default))},
	 {"in range", ?_assertEqual(1234, zabbix_sender:remote_port(1234))},
	 {"too low", ?_assertError(einval, zabbix_sender:remote_port(-1))},
	 {"too high", ?_assertError(einval, zabbix_sender:remote_port(65536))}
	].


%% Test zabbix_sender_bin/1
%% default cannot be tested here, since it expects zabbix_sender in PATH
%% ====================================================================
zabbix_sender_bin_test_() ->
	Fn = filename:absname("../test/zabbix_sender_mock"),
	FnBin = erlang:list_to_binary(Fn),
	FnWrong = "not_here",
	[
	 {"string", ?_assertEqual(Fn, zabbix_sender:zabbix_sender_bin(Fn))},
	 {"binary", ?_assertEqual(Fn, zabbix_sender:zabbix_sender_bin(FnBin))},
	 {"not found", ?_assertError([$F,$a,$i,$l|_],
								 zabbix_sender:zabbix_sender_bin(FnWrong))}
	].


%% Test error_handler/1
%% ====================================================================
error_handler_test_() ->
	F1 = zabbix_sender:error_handler({?MODULE, error_handler_1}),
	F2 = zabbix_sender:error_handler({?MODULE, error_handler_3, [x, y]}),
	F3 = zabbix_sender:error_handler(fun(M) -> {eh_fun, M} end),
	[
	 {"default", ?_assertMatch(F when is_function(F, 1), zabbix_sender:error_handler(default))}, 
	 {"error_logger", ?_assertMatch(F when is_function(F, 1), zabbix_sender:error_handler(error_logger))},
	 {"is_fun - {M,F}", ?_assert(is_function(F1, 1))},
	 {"result ok - {M,F}", ?_assertEqual({eh1, msg1}, F1(msg1))},
	 {"is_fun - {M,F,A}", ?_assert(is_function(F2, 1))},
	 {"result ok - {M,F,A}", ?_assertEqual({eh3, msg2, x, y}, F2(msg2))},
	 {"is_fun - fun", ?_assert(is_function(F3, 1))},
	 {"result ok - fun", ?_assertEqual({eh_fun, msg3}, F3(msg3))}
	].


error_handler_1(M) ->		{eh1, M}.

error_handler_3(M, X, Y) ->	{eh3, M, X, Y}.


%% Test update_resolve_timer/1
%% ====================================================================
update_resolve_timer_test_() ->
	{setup,
	 fun() ->
			 mock_timer(),
			 ok
	 end,
	 fun(_) ->
			 protofy_test_util:unmock(timer),
			 ok
	 end,
	 fun(_) ->
			 T = 10,
			 SU = #state{tref = undefined},
			 SD = #state{tref = {tref, T, zabbix_sender, resolve_remote, []}},
			 SU_OCh = SU#state{resolve_when = on_change},
			 SU_OCa = SU#state{resolve_when = on_call},
			 SU_OT = SU#state{resolve_when = {on_timer, T}},
			 SD_OCh = SD#state{resolve_when = on_change},
			 SD_OCa = SD#state{resolve_when = on_call},
			 SD_OT = SD#state{resolve_when = {on_timer, T}},
			 [
			  {"on_change, timer off", ?_assertEqual(SU_OCh, zabbix_sender:update_resolve_timer(SU_OCh))},
			  {"on_call, timer off", ?_assertEqual(SU_OCa, zabbix_sender:update_resolve_timer(SU_OCa))},
			  {"on_timer, timer off", ?_assertEqual(SD_OT, zabbix_sender:update_resolve_timer(SU_OT))},
			  {"on_change, timer on", ?_assertEqual(SU_OCh, zabbix_sender:update_resolve_timer(SD_OCh))},
			  {"on_call, timer on", ?_assertEqual(SU_OCa, zabbix_sender:update_resolve_timer(SD_OCa))},
			  {"on_timer, timer on", ?_assertEqual(SD_OT, zabbix_sender:update_resolve_timer(SD_OT))}
			 ]
	 end}.
			  

%% Test update_prepared
%% ====================================================================
update_prepared_test_() ->
	S = #state{
			   bin = "TestBin",
			   cmd_opts = [{remote_addr, "1.2.3.4"}]}, 
	?_assertEqual(S#state{cmd_format="TestBin -z \"1.2.3.4\" -k \"~s\" -o ~p"},
				  zabbix_sender:update_prepared(S)).


%% ====================================================================
%% Tests for interface functions
%% ====================================================================

%% Test start/1 unnamed, stop/1
%% ====================================================================
start_stop_unnamed_test() ->
	Info = setup(),
	Ref = ?GV(ref, Info),
	?assert(is_process_alive(Ref)),
	?assertEqual(ok, zabbix_sender:stop(Ref)),
	?assertEqual(ok, protofy_test_util:wait_for_stop(Ref, 20)).


%% Test start/1 named, stop/1
%% ====================================================================
start_stop_named_test() ->
	Ref = test_ref,
	Opts = [{remote_addr, "1.2.3.4"},
			{zabbix_sender_bin, filename:absname("../test/zabbix_sender_mock")},
			{server_ref, Ref}],
	test_named_start_stop(Ref, Opts).


%% Test start/1 singleton, stop/1
%% ====================================================================
start_stop_singleton_test() ->
	Ref = zabbix_sender,
	Opts = [{remote_addr, "1.2.3.4"},
			{zabbix_sender_bin, filename:absname("../test/zabbix_sender_mock")},
			{server_ref, singleton}],
	test_named_start_stop(Ref, Opts).


%% Worker function for named start_stop tests
%% ====================================================================
test_named_start_stop(Ref, Opts) ->
	{ok, Pid} = zabbix_sender:start_link(Opts),
	?assertEqual(Pid, whereis(Ref)),
	?assertEqual(ok, zabbix_sender:stop(Ref)),
	?assertEqual(undefined, erlang:whereis(Ref)),
	?assertEqual(ok, protofy_test_util:wait_for_stop(Pid, 20)).
		 

%% Test info/1, set_remote/5, set_local_name/2, set_zabbix_sender_bin/2,
%% send/3
%% ====================================================================
api_test_() ->
	{foreach,
	 fun setup/0,
	 fun teardown/1,
	 [
	  fun(C) -> {"info/1", fun() -> test_info(C) end} end,
	  fun(C) -> {"set_remote/5",fun() -> test_set_remote(C) end} end,
	  fun(C) -> {"set_local_name/2", fun() -> test_set_local_name(C) end} end,
	  fun(C) -> {"set_zabbix_sender_bin/2", fun() -> test_set_zabbix_sender_bin(C) end} end,
	  fun(C) -> {"set_error_handler/2", fun() -> test_set_error_handler(C) end} end,
	  fun(C) -> {"send/3", fun() -> test_send(C) end} end,
	  fun(C) -> {"send/3 error handler", fun() -> test_send_error(C) end} end
	 ]
	}.


%% Test info/1
%% ====================================================================
test_info(C) ->
	Ref = ?GV(ref, C),
	?assertEqual(?GV(info, C), zabbix_sender:info(Ref)).


%% Test set_remote/5
%% ====================================================================
test_set_remote(C) ->
	Ref = ?GV(ref, C),
	Addr = "1.1.1.1",
	Port = 1111,
	RW = on_call,
	RT = inet6,
	?assertEqual(ok, zabbix_sender:set_remote(Ref, Addr, Port, RW, RT)),
	Info = zabbix_sender:info(Ref),
	?assertEqual(Addr, ?GV(remote_addr, Info)),
	?assertEqual(Port, ?GV(remote_port, Info)),
	?assertEqual(RW, ?GV(resolve_when, Info)),
	?assertEqual(RT, ?GV(resolve_to, Info)).


%% Test set_local_name/2
%% ====================================================================
test_set_local_name(C) ->
	Ref = ?GV(ref, C),
	Name = "new_name",
	?assertNotEqual(Name, ?GV(local_name, zabbix_sender:info(Ref))),
	?assertEqual(ok, zabbix_sender:set_local_name(Ref, Name)),
	?assertEqual(Name, ?GV(local_name, zabbix_sender:info(Ref))).


%% Test set_zabbix_sender_bin/2
%% ====================================================================
test_set_zabbix_sender_bin(C) ->
	Ref = ?GV(ref, C),
	Fn = ?GV(fn, C) ++ "_2",
	?assertNotEqual(Fn, ?GV(zabbix_sender_bin, zabbix_sender:info(Ref))),	
	?assertEqual(ok, zabbix_sender:set_zabbix_sender_bin(Ref, Fn)),
	?assertEqual(Fn, ?GV(zabbix_sender_bin, zabbix_sender:info(Ref))).


%% Test set_error_handler/2 (actual error handling will be tested below)
%% ====================================================================
test_set_error_handler(C) ->
	Ref = ?GV(ref, C),
	F = fun(_Msg) -> ok end, 
	?assertEqual(ok, zabbix_sender:set_error_handler(Ref, F)).


%% Test send_test/3
%% ====================================================================
test_send(C) ->
	Ref = ?GV(ref, C),
	Key = lists:flatten(io_lib:format("~B", [crypto:rand_uniform(0, 100000)])),
	Value = crypto:rand_uniform(0, 100000),
	Log = filename:absname("../test/logs/l_" ++ Key),
	zabbix_sender:send(Ref, Key, Value),
	timer:sleep(50),
	R1 = file:read_file(Log),
	?assertEqual(ok, file:delete(Log)),
	?assertMatch({ok, _}, R1),
	{ok, Actual} = R1,
	Expected = erlang:list_to_binary(lists:flatten(io_lib:format("~B", [Value]))), 
	?assertEqual(Expected, Actual).


%% Test send_test/3 with error handling
%% ====================================================================
test_send_error(C) ->
	Ref = ?GV(ref, C),
	Self = self(),
	Eh = fun(Msg) -> Self ! Msg end,
	zabbix_sender:set_error_handler(Ref, Eh),
	zabbix_sender:send(Ref, "error_key", 0),
	Result = receive
				 X -> X
			 after
				 200 -> timeout
			 end,
	?assertEqual({zabbix_sender,"error_key",0}, ?GV(source, Result)),
	?assertEqual(sending_failed, ?GV(error, Result)).


%% Test info/0, set_remote/4, set_local_name/1, set_zabbix_sender_bin/1,
%% send/2
%% ====================================================================
singleton_api_test_() ->
	{foreach,
	 fun singleton_setup/0,
	 fun singleton_teardown/1,
	 [
	  fun(C) -> {"info/0", fun() -> singleton_test_info(C) end} end,
	  fun(C) -> {"set_remote/4", fun() -> singleton_test_set_remote(C) end} end,
	  fun(C) -> {"set_local_name/1", fun() -> singleton_test_set_local_name(C) end} end,
	  fun(C) -> {"set_zabbix_sender_bin/1", fun() -> singleton_test_set_zabbix_sender_bin(C) end} end,
	  fun(C) -> {"send/2", fun() -> singleton_test_send(C) end} end,
	  fun(C) -> {"send/2 error handler", fun() -> singleton_test_send_error(C) end} end
	 ]
	}.


%% Test info/0
%% ====================================================================
singleton_test_info(C) ->
	?assertEqual(?GV(info, C), zabbix_sender:info()).


%% Test set_remote/4
%% ====================================================================
singleton_test_set_remote(_C) ->
	Addr = "1.1.1.1",
	Port = 1111,
	RW = on_call,
	RT = inet6,
	?assertEqual(ok, zabbix_sender:set_remote(Addr, Port, RW, RT)),
	Info = zabbix_sender:info(),
	?assertEqual(Addr, ?GV(remote_addr, Info)),
	?assertEqual(Port, ?GV(remote_port, Info)),
	?assertEqual(RW, ?GV(resolve_when, Info)),
	?assertEqual(RT, ?GV(resolve_to, Info)).


%% Test set_local_name/1
%% ====================================================================
singleton_test_set_local_name(_C) ->
	Name = "new_name",
	?assertNotEqual(Name, ?GV(local_name, zabbix_sender:info())),
	?assertEqual(ok, zabbix_sender:set_local_name(Name)),
	?assertEqual(Name, ?GV(local_name, zabbix_sender:info())).


%% Test set_zabbix_sender_bin/1
%% ====================================================================
singleton_test_set_zabbix_sender_bin(C) ->
	Fn = ?GV(fn, C) ++ "_2",
	?assertNotEqual(Fn, ?GV(zabbix_sender_bin, zabbix_sender:info())),	
	?assertEqual(ok, zabbix_sender:set_zabbix_sender_bin(Fn)),
	?assertEqual(Fn, ?GV(zabbix_sender_bin, zabbix_sender:info())).


%% Test send_test/2
%% ====================================================================
singleton_test_send(_C) ->
	Key = lists:flatten(io_lib:format("~B", [crypto:rand_uniform(0, 100000)])),
	Value = crypto:rand_uniform(0, 100000),
	Log = filename:absname("../test/logs/l_" ++ Key),
	zabbix_sender:send(Key, Value),
	timer:sleep(50),
	R1 = file:read_file(Log),
	?assertMatch(ok, file:delete(Log)),
	?assertMatch({ok, _}, R1),
	{ok, Actual} = R1,
	Expected = erlang:list_to_binary(lists:flatten(io_lib:format("~B", [Value]))), 
	?assertEqual(Expected, Actual).


%% Test send/2 with error handling
%% ====================================================================
singleton_test_send_error(_C) ->
	Self = self(),
	Eh = fun(Msg) -> Self ! Msg end,
	zabbix_sender:set_error_handler(Eh),
	zabbix_sender:send("error_key", 0),
	Result = receive
				 X -> X
			 after
				 200 -> timeout
			 end,
	?assertEqual({zabbix_sender,"error_key",0}, ?GV(source, Result)),
	?assertEqual(sending_failed, ?GV(error, Result)).

	
%% ====================================================================
%% Helpers
%% ====================================================================

%% Setup server
%% ====================================================================
setup() ->
	setup([]).

setup(O) ->
	Fn = filename:absname("../test/zabbix_sender_mock"),
	Ra = "1.2.3.4",
	Opts = [{remote_addr, Ra}, {zabbix_sender_bin, Fn} | O],
	{ok, Ref} = zabbix_sender:start_link(Opts),
	Info =  [
			 {resolve_when,on_change},
			 {resolve_to,inet},
			 {zabbix_sender_bin, Fn},
			 {remote_addr, Ra}
			],
	[{ref, Ref},
	 {fn, Fn},
	 {ra, Ra},
	 {info, Info}].

singleton_setup() ->
	setup([{server_ref, singleton}]).


%% Tear down server
%% ====================================================================
teardown(C) ->
	case ?GV(ref, C) of
		undefined -> ok;
		Ref -> zabbix_sender:stop(Ref)
	end.

singleton_teardown(_C) ->
	zabbix_sender:stop().


%% ====================================================================
%% Mocks
%% ====================================================================

%% Mock filelib:is_regular/1
%% ====================================================================
mock_filelib() ->
	ok = meck:new(filelib, [unstick, passthrough]),
	ok = meck:expect(filelib, is_regular,
					 fun("regular") -> true;
						(<<"regular">>) -> true;
						(_) -> false end),
	ok.


%% Mock timer:apply_interval/4, timer:cancel/1
%% ====================================================================
mock_timer() ->
	ok = meck:new(timer, [unstick, passthrough]),
	ok = meck:expect(timer, apply_interval,
					 fun(T, M, F, A) ->
							  {ok, {tref, T, M, F, A}}
					 end),
	ok = meck:expect(timer, cancel,
					 fun({tref, _, _, _, _}) -> {ok, cancel};
						(_) -> {error, no_tref}
					 end),
	ok.

