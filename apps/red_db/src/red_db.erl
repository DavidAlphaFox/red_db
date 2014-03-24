-module(red_db).
-behaviour(gen_server).
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([db/1]).

-record(state, {
				db :: string()
        }).
-type state() :: #state{}.

-define(TABLE_TIMEOUT, 30000).

%%% =================================================================================================
%%% External functions
%%% =================================================================================================
-spec start_link(non_neg_integer()) -> {ok, pid()}.
%%% @doc starts a new db client
start_link(Index) ->
  gen_server:start_link({local,db(Index)}, ?MODULE, Index, []).
%%% =================================================================================================
%%% Server functions
%%% =================================================================================================
%%% @hidden

-spec init(non_neg_integer()) -> {ok, state()} | {stop, any()}.
init(Index) ->
	DB = db(Index),
	{ok,#state{db = DB}}.

handle_call(Any, _From, State) ->
  {reply, {ok,"R"}, State}.

handle_cast(_Any,State)->
	{noreply,State}.
%% @hidden
-spec handle_info(term(), state()) -> {noreply, state(), hibernate}.
handle_info(_, State) -> 
	{noreply, State, hibernate}.

%% @hidden
-spec terminate(term(), state()) -> ok.
terminate(_, _) -> 
	ok.

%% @hidden
-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) -> 
	{ok, State}.

-spec db(non_neg_integer()) -> atom().
db(Index) ->
  list_to_atom("red_db_" ++ integer_to_list(Index)).

