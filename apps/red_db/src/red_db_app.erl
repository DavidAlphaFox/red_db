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
    db_init(),
    red_db_sup:start_link().

stop(_State) ->
    ok.


%%% @doc get directory of mnesia
-spec mneisa_dir() -> list().
mneisa_dir() ->
 mnesia:system_info(directory).

%%% @doc check directory of mnesia exsists
-spec ensure_mnesia_dir()-> ok | no_return().
ensure_mnesia_dir() ->
    MnesiaDir = mneisa_dir() ++ "/",
    case filelib:ensure_dir(MnesiaDir) of
        {error, Reason} ->
            throw({error, {cannot_create_mnesia_dir, MnesiaDir, Reason}});
        ok ->
            ok
    end.

mnesia_init()->
	case mnesa:system_info(is_running) of
		yes ->
			application:stop(mnesia),
			ok = mnesia:create_schema([node()]),
			application:start(mnesia);
		_->
			ok = mnesia:create_schema([node()]),
			application:start(mnesia)
		end.

db_init()->
	try 
		ensure_mnesia_dir(),
		application:start(mnesia)
	catch
		error:_ ->
			mnesia_init()
	end.

