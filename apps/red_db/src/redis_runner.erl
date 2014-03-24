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
        db = 0  :: atom(),
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
    OriginalCommand = #redis_command{cmd = Cmd,
                                    args = Args},
    Command = parse_command(OriginalCommand),
    run(Command,State).

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
run(#redis_command{cmd = Cmd,result_type = ResType},State)->
  case ResType of
    number -> 
      tcp_err(<<"error test">>,State);
    string ->
      tcp_string(Cmd,State)
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


