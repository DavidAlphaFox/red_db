-module(red_db_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    {ok, _} = ranch:start_listener(redis_proxy,1,
                ranch_tcp, [{port, 6379}], redis_protocol, []),
    red_db_sup:start_link().

stop(_State) ->
    ok.
