%%%-------------------------------------------------------------------                                                          
%%% @author David.Gao <david.alpha.fox@gmail.com>                                                                                                                                     
%%% @copyright (C) 2014                                                                                  
%%% @doc redis protocol paser and runner                                                                               
%%% @end                                                                                                                        
%%%------------------------------------------------------------------
-module(redis_runner).
-behaviour(gen_server).

-include("priv/red_db.hrl").

-export([start_link/2,init/1,handle_call/3,handle_cast/2,handle_info/2,code_change/3,terminate/2]).
-export([stop/1,run/3]).
-record(state, {
				socket :: port(),
				transport :: undefined | atom(),
        db = red_db:db(0)  :: atom(),
        multi_queue = undefined   :: undefined | [{binary(), [binary()]}]
        }).
-type state() :: #state{}.

%%% @doc starts a new runner
-spec start_link(atom(),port())-> {ok, pid()}.
start_link(Transport,Socket) ->
  gen_server:start_link(?MODULE, [Transport,Socket], []).

%%% @doc stops the runner
-spec stop(pid()) -> ok.
stop(Runner) ->
  gen_server:cast(Runner, stop).
%%% @doc executes the received command  
-spec run(pid(), binary(), [binary()]) -> ok.
run(Runner, Command, Arguments) ->
  gen_server:cast(Runner, {run, Command, Arguments}).

%%% =================================================================================================
%%% Server functions
%%% =================================================================================================
%%% @hidden
-spec init(list()) -> {ok, state()}.
init([Transport,Socket]) ->
  {ok, #state{socket = Socket, transport = Transport}}.

%%% @doc don't use gen_server:call to execute redis command
%%% cast is in sequeue
-spec handle_call(X, reference(), state()) -> {stop, {unexpected_request, X}, {unexpected_request, X}, state()}.
handle_call(X, _From, State) ->
 {stop, {unexpected_request, X}, {unexpected_request, X}, State}.

-spec handle_cast(stop |  {run, binary(), [binary()]}, state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
handle_cast(stop, State) ->
  {stop, normal, State};

handle_cast({run, Cmd, Args}, State) ->
  try
    OriginalCommand = #redis_command{cmd = Cmd,
                                    args = Args},
    Command = parse_command(OriginalCommand),
    run(Command,State)
  catch
    _:Error->
    tcp_err(parse_error(Cmd, Error), State)
  end.


%% @hidden
-spec handle_info(term(), state()) -> {noreply, state(), hibernate}.
handle_info(_Info, State) ->
  {noreply, State, hibernate}.

%%% @hidden
-spec terminate(term(), state()) -> ok.
terminate(_, _) -> 
	ok.

%%% @hidden
-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) -> 
	{ok, State}.


parse_error(Cmd, unsupported) -> <<Cmd/binary, " unsupported in this version">>;
parse_error(Cmd, nested) -> <<Cmd/binary, " calls can not be nested">>;
parse_error(Cmd, out_of_multi) -> <<Cmd/binary, " without MULTI">>;
parse_error(Cmd, not_in_multi) -> <<Cmd/binary, " inside MULTI is not allowed">>;
parse_error(_Cmd, db_in_multi) -> <<"Transactions may include just one database">>;
parse_error(Cmd, out_of_pubsub) -> <<Cmd/binary, " outside PUBSUB mode is not allowed">>;
parse_error(_Cmd, not_in_pubsub) -> <<"only (P)SUBSCRIBE / (P)UNSUBSCRIBE / QUIT allowed in this context">>;
parse_error(Cmd, unknown_command) -> <<"unknown command '", Cmd/binary, "'">>;
parse_error(_Cmd, no_such_key) -> <<"no such key">>;
parse_error(_Cmd, syntax) -> <<"syntax error">>;
parse_error(_Cmd, not_integer) -> <<"value is not an integer or out of range">>;
parse_error(_Cmd, {not_integer, Field}) -> [Field, " is not an integer or out of range"];
parse_error(_Cmd, {not_float, Field}) -> [Field, " is not a double"];
parse_error(_Cmd, {out_of_range, Field}) -> [Field, " is out of range"];
parse_error(_Cmd, {is_negative, Field}) -> [Field, " is negative"];
parse_error(_Cmd, not_float) -> <<"value is not a double">>;
parse_error(_Cmd, bad_item_type) -> <<"Operation against a key holding the wrong kind of value">>;
parse_error(_Cmd, source_equals_destination) -> <<"source and destinantion objects are the same">>;
parse_error(Cmd, bad_arg_num) -> <<"wrong number of arguments for '", Cmd/binary, "' command">>;
parse_error(_Cmd, {bad_arg_num, SubCmd}) -> ["wrong number of arguments for ", SubCmd];
parse_error(_Cmd, unauthorized) -> <<"operation not permitted">>;
parse_error(_Cmd, nan_result) -> <<"resulting score is not a number (NaN)">>;
parse_error(_Cmd, auth_not_allowed) -> <<"Client sent AUTH, but no password is set">>;
parse_error(_Cmd, {error, Reason}) -> Reason;
parse_error(_Cmd, Error) -> io_lib:format("~p", [Error]).

-spec parse_command(#redis_command{args :: [binary()]}) -> #redis_command{}.
parse_command(C = #redis_command{cmd = <<"QUIT">>, args = []}) ->
 C#redis_command{result_type = ok, group=connection};
parse_command(#redis_command{cmd = <<"QUIT">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"PING">>, args = []}) -> 
  C#redis_command{result_type = string, group=connection};
parse_command(#redis_command{cmd = <<"PING">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"DECR">>, args = [_Key]}) -> 
  C#redis_command{result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"DECR">>}) ->
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"DECRBY">>, args = [Key, Decrement]}) -> 
  C#redis_command{args = [Key, binary_to_integer(Decrement)],result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"DECRBY">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"INCR">>, args = [_Key]}) -> 
  C#redis_command{result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"INCR">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"INCRBY">>, args = [Key, Increment]}) -> 
  C#redis_command{args = [Key, binary_to_integer(Increment)], result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"INCRBY">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = Any}) -> 
  C#redis_command{ result_type = string, group=strings}.

run(#redis_command{cmd = <<"QUIT">>}, State) ->
  case tcp_ok(State) of
    {noreply, NewState, hibernate} -> 
      {stop, normal, NewState};
    Error ->
      Error
  end;

run(#redis_command{cmd = <<"PING">>}, State)->
  tcp_string(<<"PONG">>,State);
run(C = #redis_command{result_type = ResType},State)->
  Res = red_db:run(State#state.db,C),
  case ResType of
    ok -> 
      tcp_ok(State);
    string ->
     tcp_string(Res, State);
    number -> 
      tcp_number(Res, State);
    boolean -> 
      tcp_boolean(Res, State)
  end.


%% @private
-spec tcp_bulk(undefined | iodata(), state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_bulk(undefined, State) ->
  tcp_send("$-1", State);
tcp_bulk(<<>>, State) ->
  tcp_send("$0\r\n", State);
tcp_bulk(Message, State) ->
  case tcp_send(["$", integer_to_list(iolist_size(Message))], State) of
    {noreply, NewState, hibernate} -> tcp_send(Message, NewState);
    Error -> Error
  end.
-spec tcp_boolean(boolean(), state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_boolean(true, State) ->
  tcp_number(1, State);
tcp_boolean(false, State) -> 
  tcp_number(0, State).
%% @private
-spec tcp_number(undefined | integer(), state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_number(undefined, State) ->
  tcp_bulk(undefined, State);
tcp_number(Number, State) ->
  tcp_send([":", integer_to_list(Number)], State).

%% @private
-spec tcp_err(binary(), state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_err(Message, State) ->
  tcp_send(["-ERR ", Message], State).

%% @private
-spec tcp_ok(state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_ok(State) ->
  tcp_string("OK", State).

%% @private
-spec tcp_string(binary(), state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_string(Message, State) ->
  tcp_send(["+", Message], State).

%% @private
-spec tcp_send(iodata(), state()) -> {noreply, state(), hibernate} | {stop, normal | {error, term()}, state()}.
tcp_send(Message, State) ->
  Transport = State#state.transport,
  Socket = State#state.socket,
  io:format("rep:~p~n",[Message]),
  try Transport:send(Socket, [Message, "\r\n"]) of
    ok ->
      {noreply, State, hibernate};
    {error, closed} ->
      {stop, normal, State};
    {error, Error} ->
      {stop, {error, Error}, State}
  catch
    _:{Exception, _} ->
      {stop, normal, State};
    _:Exception ->
      {stop, normal, State}
  end.


