using Mango
using Test
using Dates

import Mango.handle_message
import Mango.on_step

# ── Shared agent types ────────────────────────────────────────────────────────

@agent struct ConvCounterAgent
    received::Int
end

function handle_message(agent::ConvCounterAgent, _msg::Any, _meta::AbstractDict)
    agent.received += 1
end

@agent struct ConvStepAgent
    steps::Int
end

function on_step(agent::ConvStepAgent, _env::Environment, _clock::Clock, _step_size_s::Real)
    agent.steps += 1
end

@agent struct ConvMsgTypedAgent
    received_strings::Int
    received_ints::Int
end

struct ConvIntMsg
    val::Int
end

function handle_message(agent::ConvMsgTypedAgent, _msg::String, _meta::AbstractDict)
    agent.received_strings += 1
end

function handle_message(agent::ConvMsgTypedAgent, _msg::ConvIntMsg, _meta::AbstractDict)
    agent.received_ints += 1
end

@agent struct ConvMoverAgent
    dx::Float64
end

function on_step(agent::ConvMoverAgent, env::Environment, _clock::Clock, _step_size_s::Real)
    sp = env.space
    pos = location(sp, agent)
    move(sp, agent, Position2D(pos.x + agent.dx, pos.y))
end

# ── has_service ───────────────────────────────────────────────────────────────

struct MyConvService
    val::Int
end

@testset "HasServiceTrueWhenPresent" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvCounterAgent(0))

    @test !has_service(agent, MyConvService)
    add_service!(agent, MyConvService(42))
    @test has_service(agent, MyConvService)
end

@testset "HasServiceFalseForAbsent" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvCounterAgent(0))

    add_service!(agent, MyConvService(1))
    # Unrelated type is not present
    @test !has_service(agent, String)
end

# ── broadcast_to_neighbors ────────────────────────────────────────────────────

@testset "BroadcastToNeighborsSendsToAll" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    hub   = register(world, ConvCounterAgent(0))
    leaf1 = register(world, ConvCounterAgent(0))
    leaf2 = register(world, ConvCounterAgent(0))

    create_topology() do t
        n0 = add_node!(t, hub)
        n1 = add_node!(t, leaf1)
        n2 = add_node!(t, leaf2)
        add_edge!(t, n0, n1)
        add_edge!(t, n0, n2)
    end

    addrs = broadcast_to_neighbors(hub, "ping")

    activate(world) do
        step_simulation(world, 1.0)
    end

    @test leaf1.received == 1
    @test leaf2.received == 1
    @test hub.received   == 0
    @test length(addrs)  == 2
end

@testset "BroadcastToNeighborsReturnsAddresses" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    a = register(world, ConvCounterAgent(0))
    b = register(world, ConvCounterAgent(0))
    c = register(world, ConvCounterAgent(0))

    topo = complete_topology(3)
    auto_assign!(topo, world)

    addrs = broadcast_to_neighbors(a, "hello")

    @test address(b) in addrs
    @test address(c) in addrs
    @test length(addrs) == 2
end

# ── step_until ────────────────────────────────────────────────────────────────

@testset "StepUntilStopsOnCondition" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvStepAgent(0))

    n = step_until(world, w -> w[1].steps >= 3; step_size_s=1.0)

    @test agent.steps == 3
    @test n == 3
end

@testset "StepUntilRespectsMaxAdvance" begin
    world = create_world(DateTime(0))
    _agent = register(world, ConvStepAgent(0))

    # Condition is never true; should be capped by max_advance_s
    n = step_until(world, _ -> false; max_advance_s=4.0, step_size_s=1.0)

    @test n == 4
end

@testset "StepUntilReturnZeroWhenAlreadyMet" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvStepAgent(5))

    # Condition is true immediately — no steps needed
    n = step_until(world, _ -> true; step_size_s=1.0)

    @test n == 0
    @test agent.steps == 5   # unchanged
end

# ── filter_messages ───────────────────────────────────────────────────────────

@testset "FilterMessagesBySenderId" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    sender_a = register(world, ConvCounterAgent(0))
    sender_b = register(world, ConvCounterAgent(0))
    receiver = register(world, ConvCounterAgent(0))

    activate(world) do
        send_message(sender_a, "from-a", address(receiver))
        send_message(sender_b, "from-b", address(receiver))
        step_simulation(world, 1.0)
    end

    txs_a = filter_messages(world; sender_id=aid(sender_a))
    txs_b = filter_messages(world; sender_id=aid(sender_b))

    @test length(txs_a) == 1
    @test txs_a[1].content == "from-a"
    @test length(txs_b) == 1
    @test txs_b[1].content == "from-b"
end

@testset "FilterMessagesByReceiverId" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    sender    = register(world, ConvCounterAgent(0))
    receiver1 = register(world, ConvCounterAgent(0))
    receiver2 = register(world, ConvCounterAgent(0))

    activate(world) do
        send_message(sender, "to-r1", address(receiver1))
        send_message(sender, "to-r2", address(receiver2))
        step_simulation(world, 1.0)
    end

    txs = filter_messages(world; receiver_id=aid(receiver1))
    @test length(txs) == 1
    @test txs[1].content == "to-r1"
end

@testset "FilterMessagesByContentType" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    sender   = register(world, ConvCounterAgent(0))
    receiver = register(world, ConvMsgTypedAgent(0, 0))

    activate(world) do
        send_message(sender, "hello",        address(receiver))
        send_message(sender, ConvIntMsg(99), address(receiver))
        step_simulation(world, 1.0)
    end

    str_txs = filter_messages(world; content_type=String)
    int_txs = filter_messages(world; content_type=ConvIntMsg)

    @test length(str_txs) == 1
    @test length(int_txs) == 1
    @test int_txs[1].content.val == 99
end

@testset "FilterMessagesNoMatch" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    sender   = register(world, ConvCounterAgent(0))
    receiver = register(world, ConvCounterAgent(0))

    activate(world) do
        send_message(sender, "hi", address(receiver))
        step_simulation(world, 1.0)
    end

    @test isempty(filter_messages(world; sender_id="nonexistent"))
end

# ── messages_as_dict ──────────────────────────────────────────────────────────

@testset "MessagesAsDictGroupsByReceiver" begin
    comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=comm_sim)

    sender = register(world, ConvCounterAgent(0))
    r1     = register(world, ConvCounterAgent(0))
    r2     = register(world, ConvCounterAgent(0))

    activate(world) do
        send_message(sender, "m1", address(r1))
        send_message(sender, "m2", address(r1))
        send_message(sender, "m3", address(r2))
        step_simulation(world, 1.0)
    end

    d = messages_as_dict(world)

    @test haskey(d, aid(r1))
    @test haskey(d, aid(r2))
    @test length(d[aid(r1)]) == 2
    @test length(d[aid(r2)]) == 1
    @test !haskey(d, aid(sender))
end

# ── position analytics ────────────────────────────────────────────────────────

@testset "DistanceTraveledMovingAgent" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(3.0))
    sp = space(world)

    move(sp, agent, Position2D(0.0, 0.0))
    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)   # moves to (3, 0)
        step_simulation(world, 1.0)   # moves to (6, 0)
    end

    @test distance_traveled(world, agent) ≈ 6.0
end

@testset "DistanceTraveledFewerThanTwoPositions" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(1.0))

    # No record_position! called → no snapshots
    @test distance_traveled(world, agent) == 0.0
end

@testset "DisplacementMovingAgent" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(3.0))
    sp = space(world)

    move(sp, agent, Position2D(0.0, 0.0))
    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)
        step_simulation(world, 1.0)
    end

    @test displacement(world, agent) ≈ 6.0
end

@testset "DisplacementZeroWhenStationary" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(0.0))
    sp = space(world)

    move(sp, agent, Position2D(2.0, 3.0))
    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)
        step_simulation(world, 1.0)
    end

    @test displacement(world, agent) ≈ 0.0
end

@testset "AverageSpeedMovingAgent" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(3.0))
    sp = space(world)

    move(sp, agent, Position2D(0.0, 0.0))
    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)
        step_simulation(world, 1.0)
    end

    # 6.0 units over 2.0 seconds → 3.0 units/s
    @test average_speed(world, agent) ≈ 3.0
end

@testset "AverageSpeedNoPositions" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(1.0))

    @test average_speed(world, agent) == 0.0
end

@testset "TrajectoryMatrixShape" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(3.0))
    sp = space(world)

    move(sp, agent, Position2D(0.0, 5.0))
    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)
        step_simulation(world, 1.0)
    end

    mat = trajectory_matrix(world, agent)

    # 3 snapshots (t=0, t=1, t=2) × 2 columns (x, y)
    @test size(mat) == (3, 2)
    @test mat[1, 1] ≈ 0.0
    @test mat[2, 1] ≈ 3.0
    @test mat[3, 1] ≈ 6.0
    @test all(mat[:, 2] .≈ 5.0)
end

@testset "TrajectoryMatrixEmptyWhenNoPositions" begin
    world = create_world(DateTime(0))
    agent = register(world, ConvMoverAgent(1.0))

    mat = trajectory_matrix(world, agent)

    @test size(mat) == (0, 2)
end
