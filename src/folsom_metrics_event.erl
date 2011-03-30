%%%-------------------------------------------------------------------
%%% @author joe williams <j@fastip.com>
%%% @doc
%%%
%%% @end
%%% Created : 22 Mar 2011 by joe williams <j@fastip.com>
%%%-------------------------------------------------------------------
-module(folsom_metrics_event).

-behaviour(gen_event).

%% API
-export([add_handler/3,
         add_handler/4,
         add_sup_handler/3,
         add_sup_handler/4,
         delete_handler/1,
         handler_exists/1,
         notify/1,
         get_handlers/0,
         get_handlers_info/0,
         get_tagged_handlers/1,
         get_values/1,
         get_info/1,
         get_statistics/1]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
         handle_info/2, terminate/2, code_change/3]).

-record(metric, {
          id,
          size,
          tags = [],
          type = uniform,
          sample
         }).

%%%===================================================================
%%% API
%%%===================================================================

add_handler(Id, Type, Size) ->
    gen_event:add_handler(folsom_metrics_event_manager,
                          {folsom_metrics_event, Id}, [Id, Type, Size]).

add_handler(Id, Type, Size, Alpha) ->
    gen_event:add_handler(folsom_metrics_event_manager,
                          {folsom_metrics_event, Id}, [Id, Type, Size, Alpha]).

add_sup_handler(Id, Type, Size) ->
    gen_event:add_sup_handler(folsom_metrics_event_manager,
                              {folsom_metrics_event, Id}, [Id, Type, Size]).

add_sup_handler(Id, Type, Size, Alpha) ->
    gen_event:add_sup_handler(folsom_metrics_event_manager,
                              {folsom_metrics_event, Id}, [Id, Type, Size, Alpha]).

delete_handler(Id) ->
    gen_event:delete_handler(folsom_metrics_event_manager, {folsom_metrics_event, Id}, nil).

handler_exists(Id) ->
    {_, Handlers} = lists:unzip(gen_event:which_handlers(folsom_metrics_event_manager)),
    lists:member(Id, Handlers).

notify(Event) ->
    gen_event:notify(folsom_metrics_event_manager, Event).

get_handlers() ->
    {_, Handlers} = lists:unzip(gen_event:which_handlers(folsom_metrics_event_manager)),
    Handlers.

get_handlers_info() ->
    folsom_utils:get_handlers_info(?MODULE).

get_tagged_handlers(Tag) ->
    folsom_utils:get_tagged_handlers(?MODULE, Tag).
        
get_values(Id) ->
    gen_event:call(folsom_metrics_event_manager, {folsom_metrics_event,Id}, values).

get_info(Id) ->
    gen_event:call(folsom_metrics_event_manager, {folsom_metrics_event, Id}, info).

get_statistics(Id) ->
    [{Id, Values}] = get_info(Id),
    [
     {id, Id},
     {type, proplists:get_value(type, Values)},
     {size, proplists:get_value(size, Values)},
     {tags, proplists:get_value(tags, Values)},
     {min, folsom_statistics:get_min(Id)},
     {max, folsom_statistics:get_max(Id)},
     {mean, folsom_statistics:get_mean(Id)},
     {median, folsom_statistics:get_median(Id)},
     {variance, folsom_statistics:get_variance(Id)},
     {standard_deviation, folsom_statistics:get_standard_deviation(Id)},
     {skewness, folsom_statistics:get_skewness(Id)},
     {kurtosis, folsom_statistics:get_kurtosis(Id)},
     {percentile,
      [
       {75, folsom_statistics:get_percentile(Id, 0.75)},
       {95, folsom_statistics:get_percentile(Id, 0.95)},
       {99, folsom_statistics:get_percentile(Id, 0.99)},
       {999, folsom_statistics:get_percentile(Id, 0.999)}
      ]
     },
     {histogram, folsom_statistics:get_histogram(Id)}
     ].

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a new event handler is added to an event manager,
%% this function is called to initialize the event handler.
%%
%% @spec init(Args) -> {ok, State}
%% @end
%%--------------------------------------------------------------------
init([Id, uniform, Tags, Size]) ->
    Sample = folsom_sample_uniform:new(Size),
    {ok, #metric{id = Id, type = uniform, tags = Tags, size = Size, sample = Sample}};
init([Id, none, Tags, Size]) ->
    Sample = folsom_sample_none:new(Size),
    {ok, #metric{id = Id, type = none, tags = Tags, size = Size, sample = Sample}};
init([Id, exdec, Tags, Size, Alpha]) ->
    Sample = folsom_sample_exdec:new(Alpha, Size),
    {ok, #metric{id = Id, type = exdec, tags = Tags, size = Size, sample = Sample}}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives an event sent using
%% gen_event:notify/2 or gen_event:sync_notify/2, this function is
%% called for each installed event handler to handle the event.
%%
%% @spec handle_event(Event, State) ->
%%                          {ok, State} |
%%                          {swap_handler, Args1, State1, Mod2, Args2} |
%%                          remove_handler
%% @end
%%--------------------------------------------------------------------
handle_event({Id, Value}, #metric{id = Id1, type = uniform, sample = Sample} = State) when Id == Id1 ->
    NewSample = folsom_sample_uniform:update(Sample, Value),
    {ok, State#metric{
           sample = NewSample}};
handle_event({Id, Value}, #metric{id = Id1, type = exdec, sample = Sample} = State) when Id == Id1->
    NewSample = folsom_sample_exdec:update(Sample, Value),
    {ok, State#metric{
           sample = NewSample}};
handle_event({Id, Value}, #metric{id = Id1, type = none, sample = Sample} = State) when Id == Id1->
    NewSample = folsom_sample_none:update(Sample, Value),
    {ok, State#metric{
           sample = NewSample}};
handle_event(_, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives a request sent using
%% gen_event:call/3,4, this function is called for the specified
%% event handler to handle the request.
%%
%% @spec handle_call(Request, State) ->
%%                   {ok, Reply, State} |
%%                   {swap_handler, Reply, Args1, State1, Mod2, Args2} |
%%                   {remove_handler, Reply}
%% @end
%%--------------------------------------------------------------------
handle_call(info, #metric{id = Id, type = Type, tags = Tags, size = Size} = State) ->
    {ok, [{Id, [
                {size, Size},
                {tags, Tags},
                {type, Type}
               ]}], State};
handle_call(values, #metric{type = uniform, sample = Sample} = State) ->
    Values = folsom_sample_uniform:get_values(Sample),
    {ok, Values, State};
handle_call(values, #metric{type = exdec, sample = Sample} = State) ->
    Values = folsom_sample_exdec:get_values(Sample),
    {ok, Values, State};
handle_call(values, #metric{type = none, sample = Sample} = State) ->
    Values = folsom_sample_none:get_values(Sample),
    {ok, Values, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for each installed event handler when
%% an event manager receives any other message than an event or a
%% synchronous request (or a system message).
%%
%% @spec handle_info(Info, State) ->
%%                         {ok, State} |
%%                         {swap_handler, Args1, State1, Mod2, Args2} |
%%                         remove_handler
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event handler is deleted from an event manager, this
%% function is called. It should be the opposite of Module:init/1 and
%% do any necessary cleaning up.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
