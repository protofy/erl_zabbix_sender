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
%% @doc Zabbix sender server. 
%% 
%% Usage (singleton):
%% Opts = [{remote_addr, "1.2.3.4"}, {server_ref, singleton}],
%% {ok, _} = zabbix_sender:start_link(Opts),
%% zabbix_sender:send("x.y.z", 42).
%%
%% Usage (unnamed):
%% Opts = [{remote_addr, "1.2.3.4"}],
%% {ok, Pid} = zabbix_sender:start_link(Opts),
%% zabbix_sender:send(Pid, "x.y.z", 42).
%%
%% Usage (named):
%% Opts = [{remote_addr, "1.2.3.4"}, {server_ref, my_ref}],
%% {ok, _} = zabbix_sender:start_link(Opts),
%% zabbix_sender:send(myref, "x.y.z", 42).
%%
%% Options (you must either specify config_file or remote_addr, everything else is optional):
%% config_file -       path to a zabbix_sender config file zabbix_sender should use
%%
%% remote_addr -       host name or IP of the remote zabbix server
%%
%% remote_port -       port number the remote zabbix server listens to
%%
%% server_ref -        singleton | undefined | atom() (see usage examples)
%%
%% resolve -           resolve given host name on_change / default (on startup or after set_remote),
%%                     on_call (whenever you send a value, will be resolved by zabbix_sender binary)
%%                     {on_timer, X} (every X milliseconds)
%%
%% resolve_to -        resolve host name to either inet/ipv4 (default) or inet6/ipv6
%%
%% local_name -        the name of the local machine (used by zabbix to put the key-value-pair to the right host)
%%                     if default/auto is given, the machine's hostname (fdqn) will be used
%%
%% zabbix_sender_bin - the path to your zabbix_sender binary
%%                     if set to default it will be assumed that zabbix_sender can be found in PATH
%%
%% error_handler -     A function to be called if zabbix_sender encounters an error.
%%                     default / error_logger -> an error_report will be emitted
%%                     {Mod, Fun} -> Mod:Fun(Error) will be called
%%                     {Mod, Fun, [Arg1, Arg2, ...]} -> Mod:Fun(Error, Arg1, Arg2, ...) will be called
%%                     Fun (a fun()) -> Fun(Error) will be called    
%% 
%% For further information about zabbix_sender, see: https://www.zabbix.com/documentation/2.2/manpages/zabbix_sender

-module(zabbix_sender).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include_lib("protofy_common/include/protofy_common.hrl").

%% ====================================================================
%% Types
%% ====================================================================
-type opt() :: {server_ref, singleton | undefined | atom()}
             | {remote_addr, remote_addr_opt()}
             | {remote_port, remote_port_opt()}
             | {resolve, resolve_opt()}
             | {resolve_to, resolve_to_opt()}
             | {local_name, local_name_opt()}
             | {zabbix_sender_bin, zabbix_sender_bin_opt()}
             | {config_file, string() | binary()}
             | {error_handler, error_handler_opt()}.
-type remote_addr_opt() :: remote_hostname_opt()
                         | remote_ip_opt().
-type remote_hostname_opt() :: binary()
                             | string().
-type remote_ip_opt() :: inet:ip_address()
                       | binary()
                       | string().
-type remote_port_opt() :: default
                         | inet:ip_address().
-type resolve_opt() :: default
                     | on_change
                     | on_call
                     | {on_timer, pos_integer()}.
-type resolve_to_opt() :: default
                        | inet
                        | inet6
                        | ipv4
                        | ipv6.
-type local_name_opt() :: default
                        | auto
                        | string()
                        | binary().
-type zabbix_sender_bin_opt() :: default
                               | string()
                               | binary().
-type error_handler_opt() :: default
                           | error_logger
                           | {module(), function()}
                           | {module(), function(), [any()]}
                           | fun().
-type value() :: term().
-type info_item() :: {term(), term()}.

%% ====================================================================
%% API functions
%% ====================================================================
-export([
  start_link/1,
  stop/0, stop/1,
  send/2, send/3,
  info/0, info/1,
  set_remote/4, set_remote/5,
  set_local_name/1, set_local_name/2,
  set_zabbix_sender_bin/1, set_zabbix_sender_bin/2,
  set_error_handler/1, set_error_handler/2
]).

-define(SERVER, ?MODULE).
-define(DEFAULT_ZABBIX_SENDER_BIN, "zabbix_sender").
-define(DEFAULT_LOCAL_NAME, auto).
-define(DEFAULT_RESOLVE_WHEN, on_change).
-define(DEFAULT_RESOLVE_TO, inet).
-define(DEFAULT_REMOTE_PORT, 10051).
-define(RESULT_PATTERN, "^info from server: \"Processed ([0-9]+) Failed ([0-9]+)").


%% start_link/1
%% ====================================================================
%% @doc Start server
%%
%% Option {server_ref, Ref} works as follows:
%% Ref == 'singleton' -> Start singleton server making the short versions of API functions available.
%% Ref == 'undefined' -> Start unregistered server
%% Ref == Anything else -> Start registered server having Ref as registered name
%%
-spec start_link([opt()]) -> {ok, pid()} | {error, reason()}.
%% ====================================================================
start_link(Opts) ->
  case ?GV(server_ref, Opts) of
    singleton -> gen_server:start_link({local, ?SERVER}, ?MODULE, [Opts], []);
    undefined -> gen_server:start_link(?MODULE, [Opts], []);
    Ref -> gen_server:start_link({local, Ref}, ?MODULE, [Opts], [])
  end.


%% stop/0
%% ====================================================================
%% @doc Stop singleton server
-spec stop() -> ok.
%% ====================================================================
stop() ->
  stop(?SERVER).


%% stop/1
%% ====================================================================
%% @doc Stop server identified by Ref
-spec stop(server_ref()) -> ok.
%% ====================================================================
stop(Ref) ->
  gen_server:call(Ref, stop).


%% send/2
%% ====================================================================
%% @doc Send Key-Value-pair via singleton server
-spec send(key(), value()) -> ok.
%% ====================================================================
send(Key, Value) ->
  send(?SERVER, Key, Value).


%% send/3
%% ====================================================================
%% @doc Send Key-Value-pair via server identified by Ref
-spec send(server_ref(), key(), value()) -> ok.
%% ====================================================================
send(Ref, {Name, Key}, Value) ->
  set_local_name(Ref, Name),
  gen_server:cast(Ref, {send, Name, Key, Value});
send(Ref, Key, Value) ->
  gen_server:cast(Ref, {send, Key, Value}).

%% info/0
%% ====================================================================
%% @doc Return info about singleton server
-spec info() -> [info_item()].
%% ====================================================================
info() ->
  info(?SERVER).


%% info/1
%% ====================================================================
%% @doc Return info about server identified by Ref
-spec info(server_ref()) -> [info_item()].
%% ====================================================================
info(Ref) ->
  gen_server:call(Ref, info).


%% set_remote/4
%% ====================================================================
%% @doc Set remote settings of singleton server
-spec set_remote(remote_addr_opt(), remote_port_opt(), resolve_opt(), resolve_to_opt()) -> ok.
%% ====================================================================
set_remote(Addr, Port, ResolveWhen, ResolveTo) ->
  set_remote(?SERVER, Addr, Port, ResolveWhen, ResolveTo).


%% set_remote/5
%% ====================================================================
%% @doc Set remote settings of server identified by Ref
-spec set_remote(server_ref(), remote_addr_opt(), remote_port_opt(),
         resolve_opt(), resolve_to_opt()) -> ok.
%% ====================================================================
set_remote(Ref, Addr, Port, ResolveWhen, ResolveTo) ->
  gen_server:call(Ref, {set_remote,
              remote_addr(Addr, false, undefined),
              remote_port(Port),
              resolve_when(ResolveWhen),
              resolve_to(ResolveTo)}).


%% set_local_name/1
%% ====================================================================
%% @doc Set local_name setting of singleton server
-spec set_local_name(local_name_opt()) -> ok.
%% ====================================================================
set_local_name(Name) ->
  set_local_name(?SERVER, Name).


%% set_local_name/2
%% ====================================================================
%% @doc Set local_name setting of server identified by Ref
-spec set_local_name(server_ref(), local_name_opt()) -> ok.
%% ====================================================================
set_local_name(Ref, Name) ->
  gen_server:call(Ref, {set_local_name, local_name(Name)}).


%% set_zabbix_sender_bin/1
%% ====================================================================
%% @doc Set zabbix_sender_bin_setting of singleton server
-spec set_zabbix_sender_bin(zabbix_sender_bin_opt()) -> ok.
%% ====================================================================
set_zabbix_sender_bin(Path) ->
  set_zabbix_sender_bin(?SERVER, Path).


%% set_zabbix_sender_bin/2
%% ====================================================================
%% @doc Set zabbix_sender_bin setting of server identified by Ref
-spec set_zabbix_sender_bin(server_ref(), zabbix_sender_bin_opt()) -> ok.
%% ====================================================================
set_zabbix_sender_bin(Ref, Path) ->
  gen_server:call(Ref, {set_zabbix_sender_bin, zabbix_sender_bin(Path)}).


%% set_error_handler/1
%% ====================================================================
%% @doc Set error_handler of singleton server
-spec set_error_handler(error_handler_opt()) -> ok.
%% ====================================================================
set_error_handler(ErrorHandler) ->
  set_error_handler(?SERVER, ErrorHandler).


%% set_error_handler/2
%% ====================================================================
%% @doc Set error_handler of server identified by Ref
-spec set_error_handler(server_ref(), error_handler_opt()) -> ok.
%% ====================================================================
set_error_handler(Ref, ErrorHandler) ->
  gen_server:call(Ref, {set_error_handler, error_handler(ErrorHandler)}).


%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, { cmd_opts, resolve_when, resolve_to, cmd_format, bin, tref, error_handler }).

%% init/1
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:init-1">gen_server:init/1</a>
-spec init(Args :: term()) -> Result when
  Result :: {ok, State}
          | {ok, State, Timeout}
          | {ok, State, hibernate}
          | {stop, Reason :: term()}
          | ignore,
  State :: term(),
  Timeout :: non_neg_integer() | infinity.
%% ====================================================================
init([Opts]) ->
  ResolveWhen = resolve_when(?GV(resolve, Opts, ?DEFAULT_RESOLVE_WHEN)),
  ResolveTo = resolve_to(?GV(resolve_to, Opts, ?DEFAULT_RESOLVE_TO)),
  ResolveNow = (on_change =:= ResolveWhen),
  CmdOpts = [{K,V} || {K, V} <- Opts, ((K == local_name)
                                    or (K == remote_port)
                                    or (K == config_file))],
  CmdOpts1 = case ?GV(remote_addr, Opts) of
               undefined ->
                 case ?GV(config_file, CmdOpts) of
                   undefined ->
                     erlang:error("either remote_addr or config_file must be given");
                   _ ->
                     CmdOpts
                 end;
               RA ->
                 [{remote_addr, remote_addr(RA, ResolveNow, ResolveTo)} | CmdOpts]
    end,
    {ok, update_resolve_timer(
     update_prepared(
     #state{
        cmd_opts = CmdOpts1,
        resolve_when = ResolveWhen,
        resolve_to = ResolveTo,
        bin = zabbix_sender_bin(?GV(zabbix_sender_bin, Opts, ?DEFAULT_ZABBIX_SENDER_BIN)),
        error_handler = error_handler(?GV(error_handler, Opts, default))
     }))}.


%% handle_call/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_call-3">gen_server:handle_call/3</a>
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) -> Result when
  Result :: {reply, Reply, NewState}
          | {reply, Reply, NewState, Timeout}
          | {reply, Reply, NewState, hibernate}
          | {noreply, NewState}
          | {noreply, NewState, Timeout}
          | {noreply, NewState, hibernate}
          | {stop, Reason, Reply, NewState}
          | {stop, Reason, NewState},
  Reply :: term(),
  NewState :: term(),
  Timeout :: non_neg_integer() | infinity,
  Reason :: term().
%% ====================================================================
handle_call(info, _From, S) ->
  {reply, do_info(S), S};

handle_call({set_remote, Addr, Port, ResWhen, ResTo}, _From, #state{cmd_opts=CO}=S) ->
  RemoteAddr = remote_addr(Addr, (on_change =:= ResWhen), ResTo),
  CO1 = proplists:delete(remote_addr, proplists:delete(remote_port, CO)),
  S1 = update_prepared(S#state{
                 cmd_opts = [{remote_addr, RemoteAddr}, {remote_port, Port} | CO1],
                 resolve_to = ResTo,
                 resolve_when = ResWhen}),
  S2 = update_resolve_timer(S1),
  {reply, ok, S2};

handle_call({set_local_name, Name}, _From, #state{cmd_opts=CO}=S) ->
  CO1 = proplists:delete(local_name, CO),
  {reply, ok, update_prepared(S#state{cmd_opts = [{local_name, Name} | CO1]})};

handle_call({set_zabbix_sender_bin, Path}, _From, S) ->
  {reply, ok, update_prepared(S#state{bin = Path})};

handle_call({set_error_handler, ErrorHandler}, _From, S) ->
  {reply, ok, S#state{error_handler = ErrorHandler}};

handle_call(stop, _From, S) ->
  {stop, normal, ok, S};

handle_call(_Request, _From, State) ->
  {reply, {error, invalid_call}, State}.


%% handle_cast/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_cast-2">gen_server:handle_cast/2</a>
-spec handle_cast(Request :: term(), State :: term()) -> Result when
  Result :: {noreply, NewState}
          | {noreply, NewState, Timeout}
          | {noreply, NewState, hibernate}
          | {stop, Reason :: term(), NewState},
  NewState :: term(),
  Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_cast({send, Key, Value}, #state{cmd_format=Format, error_handler=EH}=S) ->
  R = os:cmd(cmd(Format, Key, Value)),
  case re:run(R, ?RESULT_PATTERN, [{capture, all_but_first, binary}, firstline]) of
    nomatch ->                EH([{source, {zabbix_sender, Key, Value}}, {error, {invalid_result, R}}]);
    {match, [_, <<"0">>]} ->  ok;
    {match, [_, _]} ->        EH([{source, {zabbix_sender, Key, Value}}, {error, sending_failed}])
  end,
  {noreply, S};

handle_cast(_Msg, State) ->
  {noreply, State}.


%% handle_info/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_info-2">gen_server:handle_info/2</a>
-spec handle_info(Info :: timeout | term(), State :: term()) -> Result when
  Result :: {noreply, NewState}
          | {noreply, NewState, Timeout}
          | {noreply, NewState, hibernate}
          | {stop, Reason :: term(), NewState},
  NewState :: term(),
  Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_info(_Info, State) ->
  {noreply, State}.


%% terminate/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:terminate-2">gen_server:terminate/2</a>
-spec terminate(Reason, State :: term()) -> Any :: term() when
  Reason :: normal
      | shutdown
      | {shutdown, term()}
      | term().
%% ====================================================================
terminate(_Reason, _State) ->
  ok.


%% code_change/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:code_change-3">gen_server:code_change/3</a>
-spec code_change(OldVsn, State :: term(), Extra :: term()) -> Result when
  Result :: {ok, NewState :: term()} | {error, Reason :: term()},
  OldVsn :: Vsn | {down, Vsn},
  Vsn :: term().
%% ====================================================================
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ====================================================================
%% Internal functions
%% ====================================================================

%% cmd_format/2
%% ====================================================================
%% @doc Prepare command format to be finalized by cmd/3.
-spec cmd_format(Bin :: string(), Opts :: [{atom(), any()}]) -> string().
%% ====================================================================
cmd_format(Bin, Opts) ->
  cmd_format(Bin, Opts, []).


%% cmd_format/3
%% ====================================================================
%% @doc Worker function for cmd_format/2
-spec cmd_format(Bin :: string, Opts :: [{atom(), any()}], A :: list()) -> string().
%% ====================================================================
cmd_format(Bin, [], A) ->
  lists:flatten(Bin ++ A ++ " -k \"~s\" -o ~p");

cmd_format(Bin, [{config_file, X}|T], A) ->
  case filelib:is_regular(X) of
    true ->
      cmd_format(Bin, T, io_lib:format(" -c \"~s\"", [X]) ++ A);
    false ->
      erlang:error(enoent)
  end;

cmd_format(Bin, [{remote_addr, X}|T], A) ->
  cmd_format(Bin, T, io_lib:format(" -z \"~s\"", [X]) ++ A);

cmd_format(Bin, [{remote_port, X}|T], A) ->
  Port = protofy_inet:port_number(X),
  cmd_format(Bin, T, io_lib:format(" -p \"~B\"", [Port]) ++ A);

cmd_format(Bin, [{local_name, X}|T], A) ->
  cmd_format(Bin, T, io_lib:format(" -s \"~s\"", [X]) ++ A).


%% cmd/3
%% ====================================================================
%% @doc Finalized command formatting to be executed by os:cmd/1
-spec cmd(Format :: string(), key(), value()) -> string().
%% ====================================================================
cmd(Format, Key, Value) ->
  lists:flatten(io_lib:format(Format, [Key, Value])).


%% do_info/1
%% ====================================================================
%% @doc info/0, info/1 worker function
-spec do_info(#state{}) -> [{atom(), any()}].
%% ====================================================================
do_info(#state{cmd_opts = CO, resolve_when = RW, resolve_to = RT, bin = Bin}) ->
  [{resolve_when, RW},
   {resolve_to, RT},
   {zabbix_sender_bin, Bin}
  | CO].


%% resolve_when/1
%% ====================================================================
%% @doc Validate and convert resolve_opt() to internal setting
-spec resolve_when(resolve_opt()) -> on_change | on_call | {on_timer, pos_integer}.
%% ====================================================================
resolve_when(default) ->                                  ?DEFAULT_RESOLVE_WHEN;
resolve_when(on_change) ->                                on_change;
resolve_when(on_call) ->                                  on_call;
resolve_when({on_timer, X}) when is_integer(X), X > 0 ->  {on_timer, X}.


%% resolve_to/1
%% ====================================================================
%% @doc Validate and convert resolve_to_opt() to internal setting
-spec resolve_to(resolve_to_opt()) -> inet | inet6.
%% ====================================================================
resolve_to(default) ->  ?DEFAULT_RESOLVE_TO;
resolve_to(inet) ->     inet;
resolve_to(inet6) ->    inet6;
resolve_to(ipv4) ->     inet;
resolve_to(ipv6) ->     inet6.


%% local_name/1
%% ====================================================================
%% @doc Validate and convert local_name_opt() to intenral setting
%%
%% Will use machine's hostname if set to auto (or default)
-spec local_name(local_name_opt()) -> string().
%% ====================================================================
local_name(default) ->
  local_name(auto);

local_name(auto) ->
  string:strip(os:cmd("hostname -f"), right, $\n);

local_name(Name) when is_binary(Name) ->
  erlang:binary_to_list(Name);

local_name(Name) when is_list(Name) ->
  case io_lib:printable_list(Name) of
    true -> Name;
    false -> erlang:error("Invalid Name (must be printable)")
  end.


%% remote_addr/3
%% ====================================================================
%% @doc Validate and convert remote_addr_opt() to internal setting
-spec remote_addr(remote_addr_opt(), ResolveNow, To) -> string() when
  ResolveNow :: boolean(),
  To :: inet | inet6.
%% ====================================================================
remote_addr(Addr, Resolve, To) when is_binary(Addr) ->
  remote_addr(erlang:binary_to_list(Addr), Resolve, To);

remote_addr(Addr, true, To) when is_list(Addr) ->
  case inet:getaddr(Addr, To) of
    {ok, IP} -> inet:ntoa(IP);
    {error, Reason} -> erlang:error(Reason)
  end;

remote_addr(Addr, false, _) when is_list(Addr) ->
  Addr.


%% remote_port/1
%% ====================================================================
%% @doc Validate and convert remote_port_opt() to internal setting
-spec remote_port(remote_port_opt()) -> inet:port_number().
%% ====================================================================
remote_port(default) ->
  remote_port(?DEFAULT_REMOTE_PORT);

remote_port(Port) ->
  protofy_inet:port_number(Port).


%% zabbix_sender_bin/1
%% ====================================================================
%% @doc Validate and convert zabbix_sender_opt() to internal setting
-spec zabbix_sender_bin(zabbix_sender_bin_opt()) -> string().
%% ====================================================================
zabbix_sender_bin(default) ->
  zabbix_sender_bin(?DEFAULT_ZABBIX_SENDER_BIN);

zabbix_sender_bin(Path) when is_binary(Path) ->
  zabbix_sender_bin(erlang:binary_to_list(Path));

zabbix_sender_bin(Path) when is_list(Path) ->
  case os:find_executable(Path) of
    false ->
      AbsPath = filename:absname(Path),
      Dir = filename:dirname(AbsPath),
      Filename = filename:basename(AbsPath),
      case os:find_executable(Filename, Dir) of
        false ->
          erlang:error(
            lists:flatten(
            io_lib:format("Failed to find executable at '~s' ('~s')", [Path, AbsPath])));
        Found -> Found
      end;
    Found -> Found
  end.


%% error_handler/1
%% ====================================================================
%% @doc Validate and convert error_handler_opt() to internal function
-spec error_handler(error_handler_opt()) -> fun().
%% ====================================================================
error_handler(default) ->       error_handler(error_logger);
error_handler(error_logger) ->  fun error_logger:error_report/1;
error_handler({M,F}) ->         fun(Msg) -> erlang:apply(M, F, [Msg]) end;
error_handler({M,F,Args}) ->    fun(Msg) -> erlang:apply(M, F, [Msg | Args])end;
error_handler(Fun) when is_function(Fun, 1) ->  Fun.


%% update_resolve_timer/1
%% ====================================================================
%% @doc Start/stop resolve timer according to setting and 
%% return updated state
-spec update_resolve_timer(#state{}) -> #state{}.
%% ====================================================================
%% no timer, setting {on_timer, T} -> start timer
update_resolve_timer(#state{tref=undefined, resolve_when={on_timer, T}}=S) ->
  {ok, TRef} = timer:apply_interval(T, ?MODULE, resolve_remote, []),
  S#state{tref = TRef};

%% active timer, {on_timer, T} -> stop old timer, start new timer
update_resolve_timer(#state{tref=TRef, resolve_when={on_timer, _}}=S) ->
  {ok, cancel} = timer:cancel(TRef),
  update_resolve_timer(S#state{tref=undefined});

%% no timer, setting not {on_timer, _} -> do nothing
update_resolve_timer(#state{tref=undefined}=S) ->
  S;

%% active timer, setting not {on_timer, _} -> stop timer
update_resolve_timer(#state{tref=Tref}=S) ->
  {ok, cancel} = timer:cancel(Tref),
  S#state{tref = undefined}.


%% update_prepared/1
%% ====================================================================
%% @doc Recalculate prepared data and update state accordingly
%%
%% Use when bin or cmd_opts changed.
-spec update_prepared(#state{}) -> #state{}.
%% ====================================================================
update_prepared(#state{bin=Bin, cmd_opts=CO}=S) ->
  S#state{cmd_format = cmd_format(Bin, CO)}.

