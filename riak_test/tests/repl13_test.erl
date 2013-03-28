-module(repl13_test).

-export([confirm/0]).
-include_lib("eunit/include/eunit.hrl").

-define(TEST_BUCKET, "riak-test-bucket").
-define(OBJ_SIZE, 4194304).

confirm() ->
    {UserConfig, {RiakNodes, _CSNodes, _Stanchion}} = rtcs:setup2x2(),
    lager:info("UserConfig = ~p", [UserConfig]),
    [A,B,C,D] = RiakNodes,

    ANodes = [A,B],
    BNodes = [C,D],

    AFirst = hd(ANodes),
    BFirst = hd(BNodes),

    lager:info("Name cluster A"),
    repl_helpers:name_cluster(AFirst, "A"),

    lager:info("Name cluster B"),
    repl_helpers:name_cluster(BFirst, "B"),

    rt:wait_until_ring_converged(ANodes),
    rt:wait_until_ring_converged(BNodes),

    lager:info("waiting for leader to converge on cluster A"),
    ?assertEqual(ok, repl_util:wait_until_leader_converge(ANodes)),
    lager:info("waiting for leader to converge on cluster B"),
    ?assertEqual(ok, repl_util:wait_until_leader_converge(BNodes)),

    {AccessKeyId, SecretAccessKey} = rtcs:create_user(AFirst, 1),
    {AccessKeyId2, SecretAccessKey2} = rtcs:create_user(BFirst, 2),

    %% User 1, Cluster 1 config
    U1C1Config = rtcs:config(AccessKeyId, SecretAccessKey, rtcs:cs_port(hd(ANodes))),
    %% User 2, Cluster 1 config
    U2C1Config = rtcs:config(AccessKeyId2, SecretAccessKey2, rtcs:cs_port(hd(ANodes))),


    %% User 1, Cluster 2 config
    U1C2Config = rtcs:config(AccessKeyId, SecretAccessKey, rtcs:cs_port(hd(BNodes))),
    %% User 2, Cluster 2 config
    U2C2Config = rtcs:config(AccessKeyId2, SecretAccessKey2, rtcs:cs_port(hd(BNodes))),


    lager:info("User 1 IS valid on the primary cluster, and has no buckets"),
    ?assertEqual([{buckets, []}], erlcloud_s3:list_buckets(U1C1Config)),

    lager:info("User 2 IS valid on the primary cluster, and has no buckets"),
    ?assertEqual([{buckets, []}], erlcloud_s3:list_buckets(U2C1Config)),

    lager:info("User 2 is NOT valid on the secondary cluster"),
    ?assertError({aws_error, _}, erlcloud_s3:list_buckets(U2C2Config)),

    lager:info("creating bucket ~p", [?TEST_BUCKET]),
    ?assertEqual(ok, erlcloud_s3:create_bucket(?TEST_BUCKET, U1C1Config)),

    ?assertMatch([{buckets, [[{name, ?TEST_BUCKET}, _]]}],
        erlcloud_s3:list_buckets(U1C1Config)),

    ObjList1= erlcloud_s3:list_objects(?TEST_BUCKET, U1C1Config),
    ?assertEqual([], proplists:get_value(contents, ObjList1)),

    Object1 = crypto:rand_bytes(?OBJ_SIZE),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_one", Object1, U1C1Config),

    ObjList2 = erlcloud_s3:list_objects(?TEST_BUCKET, U1C1Config),

    ?assertEqual(["object_one"],
        [proplists:get_value(key, O) ||
            O <- proplists:get_value(contents, ObjList2)]),

    Obj = erlcloud_s3:get_object(?TEST_BUCKET, "object_one", U1C1Config),
    ?assertEqual(Object1, proplists:get_value(content, Obj)),

    lager:info("set up replication between clusters"),


    %% get the leader for the first cluster
    LeaderA = rpc:call(AFirst, riak_core_cluster_mgr, get_leader, []),

    {ok, {_IP, BPort}} = rpc:call(BFirst, application, get_env,
                                 [riak_core, cluster_mgr]),
    connect_clusters(LeaderA, ANodes, BPort, "B"),

    Status = rpc:call(LeaderA, riak_repl_console, status, [quiet]),

    case proplists:get_value(proxy_get_enabled, Status) of
        undefined -> lager:info("PG NOT ENABLED FOR CLUSTER");
        EnabledFor -> lager:info("PG enabled for cluster ~p",[EnabledFor])
    end,

    rt:wait_until_ring_converged(ANodes),

    lager:info("Starting fullsync"),
    start_and_wait_until_fullsync_complete13(LeaderA),
    lager:info("User 2 is valid on secondary cluster after fullsync,"
               " still no buckets"),
    ?assertEqual([{buckets, []}], erlcloud_s3:list_buckets(U2C2Config)),

    lager:info("User 1 has the test bucket on the secondary cluster now"),
    ?assertMatch([{buckets, [[{name, ?TEST_BUCKET}, _]]}],
        erlcloud_s3:list_buckets(U1C2Config)),

    lager:info("Object written on primary cluster is readable from secondary "
        "cluster"),
    Obj2 = erlcloud_s3:get_object(?TEST_BUCKET, "object_one", U1C2Config),
    ?assertEqual(Object1, proplists:get_value(content, Obj2)),

    lager:info("write 2 more objects to the primary cluster"),

    Object2 = crypto:rand_bytes(?OBJ_SIZE),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_two", Object2, U1C1Config),

    Object3 = crypto:rand_bytes(?OBJ_SIZE),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_three", Object3, U1C1Config),

    lager:info("disconnect the clusters"),
    disconnect_clusters(LeaderA, ANodes, "B"),

    timer:sleep(5000),

    lager:info("check we can still read the fullsynced object"),

    Obj3 = erlcloud_s3:get_object(?TEST_BUCKET, "object_one", U1C2Config),
    ?assertEqual(Object1, proplists:get_value(content,Obj3)),

    lager:info("check all 3 objects are listed on the secondary cluster"),
    ?assertEqual(["object_one", "object_three", "object_two"],
        [proplists:get_value(key, O) || O <- proplists:get_value(contents,
                erlcloud_s3:list_objects(?TEST_BUCKET, U1C2Config))]),

    lager:info("check that the 2 other objects can't be read"),
    %% XXX I expect errors here, but I get successful objects containing <<>>
    %?assertError({aws_error, _}, erlcloud_s3:get_object(?TEST_BUCKET,
    %        "object_two")),
    %?assertError({aws_error, _}, erlcloud_s3:get_object(?TEST_BUCKET,
    %        "object_three")),

    Obj4 = erlcloud_s3:get_object(?TEST_BUCKET, "object_two", U1C2Config),

    % Check content of Obj4
    ?assertEqual(<<>>, proplists:get_value(content, Obj4)),
    %Check content_length of Obj4
    ?assertEqual(integer_to_list(byte_size(Object2)),
        proplists:get_value(content_length, Obj4)),

    Obj5 = erlcloud_s3:get_object(?TEST_BUCKET, "object_three", U1C2Config),

    % Check content of Obj5
    ?assertEqual(<<>>, proplists:get_value(content, Obj5)),
    % Check content_length of Obj5
    ?assertEqual(integer_to_list(byte_size(Object3)),
        proplists:get_value(content_length, Obj5)),

    lager:info("reconnect clusters"),
    connect_clusters(LeaderA, ANodes, BPort, "B"),

    %%lager:info("CONFIG ~p", [U1C2Config]),
    lager:info("check we can read object_two via proxy get"),
    Obj6 = erlcloud_s3:get_object(?TEST_BUCKET, "object_two", U1C2Config),
    ?assertEqual(Object2, proplists:get_value(content, Obj6)),
    lager:info("disconnect the clusters again"),
    disconnect_clusters(LeaderA, ANodes, "B"),


    lager:info("check we still can't read object_three"),
    Obj7 = erlcloud_s3:get_object(?TEST_BUCKET, "object_three", U1C2Config),
    ?assertEqual(<<>>, proplists:get_value(content, Obj7)),

    lager:info("check that proxy getting object_two wrote it locally, so we"
        " can read it"),
    Obj8 = erlcloud_s3:get_object(?TEST_BUCKET, "object_two", U1C2Config),
    ?assertEqual(Object2, proplists:get_value(content, Obj8)),

    lager:info("delete object_one while clusters are disconnected"),
    erlcloud_s3:delete_object(?TEST_BUCKET, "object_one", U1C1Config),

    lager:info("reconnect clusters"),
    connect_clusters(LeaderA, ANodes, BPort, "B"),

    lager:info("delete object_two while clusters are connected"),
    erlcloud_s3:delete_object(?TEST_BUCKET, "object_two", U1C1Config),

    lager:info("object_one is still visible on secondary cluster"),
    Obj9 = erlcloud_s3:get_object(?TEST_BUCKET, "object_one", U1C2Config),
    ?assertEqual(Object1, proplists:get_value(content, Obj9)),

    lager:info("object_two is deleted"),
    ?assertError({aws_error, _},
                 erlcloud_s3:get_object(?TEST_BUCKET, "object_two", U1C2Config)),

    start_and_wait_until_fullsync_complete13(LeaderA),

    lager:info("object_one is deleted after fullsync"),
    ?assertError({aws_error, _},
                 erlcloud_s3:get_object(?TEST_BUCKET, "object_one", U1C2Config)),

    lager:info("disconnect the clusters again"),
    disconnect_clusters(LeaderA, ANodes, "B"),

    Object3A = crypto:rand_bytes(?OBJ_SIZE),
    ?assert(Object3 /= Object3A),

    lager:info("write a new version of object_three"),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_three", Object3A, U1C1Config),

    lager:info("Independently write different object_four and object_five to bolth clusters"),

    Object4A = crypto:rand_bytes(?OBJ_SIZE),
    Object4B = crypto:rand_bytes(?OBJ_SIZE),

    Object5A = crypto:rand_bytes(?OBJ_SIZE),
    Object5B = crypto:rand_bytes(?OBJ_SIZE),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_four", Object4A, U1C1Config),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_four", Object4B, U1C2Config),
    erlcloud_s3:put_object(?TEST_BUCKET, "object_five", Object5B, U1C2Config),

    lager:info("delay writing object 5 on primary cluster 1 second after "
        "writing to secondary cluster"),
    timer:sleep(1000),
    erlcloud_s3:put_object(?TEST_BUCKET, "object_five", Object5A, U1C1Config),

    lager:info("reconnect clusters"),
    connect_clusters(LeaderA, ANodes, BPort, "B"),

    lager:info("secondary cluster has old version of object three"),
    Obj10 = erlcloud_s3:get_object(?TEST_BUCKET, "object_three", U1C2Config),
    ?assertEqual(Object3, proplists:get_value(content, Obj10)),

    lager:info("secondary cluster has 'B' version of object four"),
    Obj11 = erlcloud_s3:get_object(?TEST_BUCKET, "object_four", U1C2Config),
    ?assertEqual(Object4B, proplists:get_value(content, Obj11)),

    start_and_wait_until_fullsync_complete13(LeaderA),

    lager:info("secondary cluster has new version of object three"),
    Obj12 = erlcloud_s3:get_object(?TEST_BUCKET, "object_three", U1C2Config),
    ?assertEqual(Object3A, proplists:get_value(content, Obj12)),

    lager:info("secondary cluster has 'B' version of object four"),
    Obj13 = erlcloud_s3:get_object(?TEST_BUCKET, "object_four", U1C2Config),
    ?assertEqual(Object4B, proplists:get_value(content, Obj13)),

    lager:info("secondary cluster has 'A' version of object five, because it "
        "was written later"),
    Obj14 = erlcloud_s3:get_object(?TEST_BUCKET, "object_five", U1C2Config),
    ?assertEqual(Object5A, proplists:get_value(content, Obj14)),

    lager:info("write 'A' version of object four again on primary cluster"),

    erlcloud_s3:put_object(?TEST_BUCKET, "object_four", Object4A, U1C1Config),

    lager:info("secondary cluster now has 'A' version of object four"),

    Obj15 = erlcloud_s3:get_object(?TEST_BUCKET, "object_four", U1C2Config),
    ?assertEqual(Object4A, proplists:get_value(content,Obj15)),

    pass.

connect_clusters(LeaderA, ANodes, BPort, Name) ->
    lager:info("Connecting to ~p", [Name]),
    connect_cluster(LeaderA, "127.0.0.1", BPort),
    ?assertEqual(ok, wait_for_connection(LeaderA, Name)),
    repl_util:enable_realtime(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    repl_util:start_realtime(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    repl_util:enable_fullsync(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    enable_pg(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    ?assertEqual(ok, wait_for_connection(LeaderA, Name)),
    rt:wait_until_ring_converged(ANodes).

disconnect_clusters(LeaderA, ANodes, Name) ->
    lager:info("Disconnecting from ~p", [Name]),
    disconnect_cluster(LeaderA, Name),
    repl_util:disable_realtime(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    repl_util:stop_realtime(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    disable_pg(LeaderA, Name),
    rt:wait_until_ring_converged(ANodes),
    ?assertEqual(ok, wait_until_no_connection(LeaderA)),
    rt:wait_until_ring_converged(ANodes).

start_and_wait_until_fullsync_complete13(Node) ->
    Status0 = rpc:call(Node, riak_repl_console, status, [quiet]),
    Count = proplists:get_value(server_fullsyncs, Status0) + 1,
    lager:info("waiting for fullsync count to be ~p", [Count]),

    lager:info("Starting fullsync on ~p (~p)", [Node,
            rtdev:node_version(rtdev:node_id(Node))]),
    rpc:call(Node, riak_repl_console, fullsync, [["start"]]),
    %% sleep because of the old bug where stats will crash if you call it too
    %% soon after starting a fullsync
    timer:sleep(500),

    Res = rt:wait_until(Node,
        fun(_) ->
                Status = rpc:call(Node, riak_repl_console, status, [quiet]),
                case proplists:get_value(server_fullsyncs, Status) of
                    C when C >= Count ->
                        true;
                    _ ->
                        false
                end
        end),
    ?assertEqual(ok, Res),

    lager:info("Fullsync on ~p complete", [Node]).

wait_for_connection(Node, Name) ->
    rt:wait_until(Node,
        fun(_) ->
                {ok, Connections} = rpc:call(Node, riak_core_cluster_mgr,
                    get_connections, []),
                lists:any(fun({{cluster_by_name, N}, _}) when N == Name -> true;
                        (_) -> false
                    end, Connections)
        end).

wait_until_no_connection(Node) ->
    rt:wait_until(Node,
        fun(_) ->
                Status = rpc:call(Node, riak_repl_console, status, [quiet]),
                case proplists:get_value(connected_clusters, Status) of
                    [] ->
                        true;
                    _ ->
                        false
                end
        end). %% 40 seconds is enough for repl

connect_cluster(Node, IP, Port) ->
    Res = rpc:call(Node, riak_repl_console, connect,
        [[IP, integer_to_list(Port)]]),
    ?assertEqual(ok, Res).

disconnect_cluster(Node, Name) ->
    Res = rpc:call(Node, riak_repl_console, disconnect,
        [[Name]]),
    ?assertEqual(ok, Res).

enable_pg(Node, Cluster) ->
    Res = rpc:call(Node, riak_repl_console, proxy_get, [["enable", Cluster]]),
    ?assertEqual(ok, Res).

disable_pg(Node, Cluster) ->
    Res = rpc:call(Node, riak_repl_console, proxy_get, [["disable", Cluster]]),
    ?assertEqual(ok, Res).


