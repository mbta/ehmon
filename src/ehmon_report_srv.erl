%%%-------------------------------------------------------------------
%% @copyright Geoff Cant
%% @author Geoff Cant <nem@erlang.geek.nz>
%% @version {@vsn}, {@date} {@time}
%% @doc
%% @end
%%%-------------------------------------------------------------------
-module(ehmon_report_srv).

-behaviour(gen_server).

-include("ehmon_log.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/0
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {tref = undefined, scheduler_time = undefined}).

-define(REPORT_MSG, report).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link(?MODULE, [], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init([]) ->
    erlang:system_flag(scheduler_wall_time, true),
    {ok, start_timer(#state{scheduler_time=erlang:statistics(scheduler_wall_time)})}.

%% @private
handle_call(report_now, _From,
            State = #state{tref=TREF, scheduler_time=LastSchedulerTime}) ->
    erlang:cancel_timer(TREF),
    CurrentSchedulerTime = erlang:statistics(scheduler_wall_time),
    do_report({LastSchedulerTime, CurrentSchedulerTime}),
    {reply, ok, start_timer(State#state{tref=undefined})};

handle_call(time_to_next_report, _From, State = #state{tref=TREF}) ->
    {reply, erlang:read_timer(TREF), State};

handle_call(Call, _From, State) ->
    ?WARN("Unexpected call ~p.", [Call]),
    {noreply, State}.

%% @private
handle_cast(Msg, State) ->
    ?WARN("Unexpected cast ~p", [Msg]),
    {noreply, State}.

%% @private
handle_info({timeout, Ref, ?REPORT_MSG},
            State = #state{tref=Ref,scheduler_time=LastSchedulerTime}) ->
    CurrentSchedulerTime = erlang:statistics(scheduler_wall_time),
    do_report({LastSchedulerTime, CurrentSchedulerTime}),
    {noreply, start_timer(State#state{tref=undefined,
                                      scheduler_time=CurrentSchedulerTime})};
handle_info(Info, State) ->
    ?WARN("Unexpected info ~p", [Info]),
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

do_report(SchedulerTimes) ->
    try
        {M, F} = ehmon_app:config(report_mf, {ehmon, send_report}),
        erlang:apply(M, F, [ehmon:report(SchedulerTimes)])
    catch
        Class:Err ->
            ?ERR("class=~p err=~p stack=\"~p\"",
                 [Class, Err, erlang:get_stacktrace()])
    end.


start_timer(State = #state{tref=undefined}) ->
    Interval = timer:seconds(ehmon_app:config(report_interval)),
    TRef = erlang:start_timer(Interval, self(), ?REPORT_MSG),
    State#state{tref=TRef}.
