using Mango
using Test
using Dates

import Mango.on_step
import Mango.handle_message

# ── Stub space for testing the default has_position fallback ──────────────────

struct RecStubPosition <: Position end
struct RecStubSpace <: Space{RecStubPosition} end

# ── Agent and role definitions ────────────────────────────────────────────────

@agent struct RecStaticAgentA
    value::Int
end

@agent struct RecStaticAgentB
    value::Int
end

@agent struct RecMoverAgent
    dx::Float64
end

function on_step(agent::RecMoverAgent, env::Environment, _clock::Clock, _step_size_s::Real)
    sp = env.space
    pos = location(sp, agent)
    move(sp, agent, Position2D(pos.x + agent.dx, pos.y))
end

@role struct RecSpecialRole
    val::Int
end

@agent struct RecRoleAgent
    value::Int
end

@agent struct RecNoRoleAgent
    value::Int
end

@agent struct RecTxSender
    sent::Int
end

@agent struct RecTxReceiver
    received::Int
end

function handle_message(agent::RecTxReceiver, _msg::Any, _meta::AbstractDict)
    agent.received += 1
end

# ── has_position ──────────────────────────────────────────────────────────────

@testset "HasPositionDefaultFalse" begin
    # Custom Space subtype that does not override has_position should return false
    stub_space = RecStubSpace()
    world = create_world(DateTime(0))
    agent = register(world, RecStaticAgentA(0))
    @test !has_position(stub_space, agent)
end

@testset "HasPositionArea2D" begin
    world = create_world(DateTime(0))
    agent = register(world, RecStaticAgentA(1))
    sp = space(world)

    # Before any move the agent has no registered position
    @test !has_position(sp, agent)

    # After move it is registered
    move(sp, agent, Position2D(3.0, 4.0))
    @test has_position(sp, agent)
end

# ── initialize preserves pre-set positions ────────────────────────────────────

@testset "InitializePreservesExistingPositions" begin
    world = create_world(DateTime(0))
    agent = register(world, RecStaticAgentA(2))
    sp = space(world)

    expected = Position2D(7.0, 8.0)
    move(sp, agent, expected)

    activate(world) do
        step_simulation(world, 1.0)
    end

    # The pre-set position must not be overwritten by random initialisation
    @test location(sp, agent) == expected
end

# ── record_position! — all agents ─────────────────────────────────────────────

@testset "RecordPositionAllAgents" begin
    world = create_world(DateTime(0))
    a1 = register(world, RecStaticAgentA(0))
    a2 = register(world, RecStaticAgentA(0))

    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)
        step_simulation(world, 1.0)
    end

    pos_hist = position_history(world)

    @test haskey(pos_hist.timeseries, aid(a1))
    @test haskey(pos_hist.timeseries, aid(a2))

    # 3 snapshots: t=0 (recorded during init), t=1, t=2
    @test length(pos_hist.time) == 3
    @test length(pos_hist.timeseries[aid(a1)]) == 3
end

# ── record_position! — with filter ───────────────────────────────────────────

@testset "RecordPositionWithFilter" begin
    world = create_world(DateTime(0))
    a_yes = register(world, RecStaticAgentA(0))
    a_no  = register(world, RecStaticAgentB(0))

    record_position!(world, filter = a -> a isa RecStaticAgentA)

    activate(world) do
        step_simulation(world, 1.0)
    end

    pos_hist = position_history(world)

    @test haskey(pos_hist.timeseries, aid(a_yes))
    @test !haskey(pos_hist.timeseries, aid(a_no))
end

# ── position_history — custom key ─────────────────────────────────────────────

@testset "PositionHistoryCustomKey" begin
    world = create_world(DateTime(0))
    a = register(world, RecStaticAgentA(0))

    record_position!(world, "mytrack")

    activate(world) do
        step_simulation(world, 1.0)
    end

    hist = position_history(world, "mytrack")

    @test !isempty(hist.time)
    @test haskey(hist.timeseries, aid(a))
end

# ── record_position! — tracks actual movement ─────────────────────────────────

@testset "RecordPositionTrackMovement" begin
    world = create_world(DateTime(0))
    agent = register(world, RecMoverAgent(3.0))
    sp = space(world)

    # Fix the starting position so the test is deterministic
    move(sp, agent, Position2D(0.0, 5.0))

    record_position!(world)

    activate(world) do
        step_simulation(world, 1.0)   # on_step moves +3 in x
        step_simulation(world, 1.0)   # on_step moves another +3 in x
    end

    series = position_history(world).timeseries[aid(agent)]
    # series[1] = (0, 5) at t=0  (before first on_step)
    # series[2] = (3, 5) at t=1
    # series[3] = (6, 5) at t=2
    @test series[1] == Position2D(0.0, 5.0)
    @test series[2].x - series[1].x ≈ 3.0
    @test series[3].x - series[2].x ≈ 3.0
    @test all(p -> p.y == 5.0, series)
end

# ── record_agent_having! — by role type ───────────────────────────────────────

@testset "RecordAgentHavingByRole" begin
    world = create_world(DateTime(0))
    a_with    = register(world, RecRoleAgent(0))
    a_without = register(world, RecNoRoleAgent(0))
    add(a_with, RecSpecialRole(42))

    record_agent_having!(world, "spec_vals", RecSpecialRole) do a
        a[RecSpecialRole].val
    end

    activate(world) do
        step_simulation(world, 1.0)
    end

    rec = data_agent_collection(world, "spec_vals")

    @test haskey(rec.timeseries, aid(a_with))
    @test !haskey(rec.timeseries, aid(a_without))
    @test all(v -> v == 42, rec.timeseries[aid(a_with)])
end

# ── record_agent_having! — by aid_contains ────────────────────────────────────

@testset "RecordAgentHavingAidContains" begin
    world = create_world(DateTime(0))
    a_match = register(world, RecRoleAgent(10), "special-agent")
    a_other = register(world, RecRoleAgent(20), "regular-agent")
    add(a_match, RecSpecialRole(1))
    add(a_other, RecSpecialRole(2))

    record_agent_having!(world, "aidfiltered", RecSpecialRole; aid_contains="special") do a
        a[RecSpecialRole].val
    end

    activate(world) do
        step_simulation(world, 1.0)
    end

    rec = data_agent_collection(world, "aidfiltered")

    @test haskey(rec.timeseries, "special-agent")
    @test !haskey(rec.timeseries, "regular-agent")
end

# ── agent_recordings_as_dict ──────────────────────────────────────────────────

@testset "AgentRecordingsAsDict" begin
    world = create_world(DateTime(0))
    a1 = register(world, RecStaticAgentA(7), "dict-a1")
    a2 = register(world, RecStaticAgentA(9), "dict-a2")

    record_agent!(world, "vals") do a
        a.value
    end

    activate(world) do
        step_simulation(world, 1.0)
    end

    d = agent_recordings_as_dict(world)

    @test haskey(d, "vals-dict-a1")
    @test haskey(d, "vals-dict-a2")
    @test haskey(d, "time")
    @test !isempty(d["time"])
    # The recorded values should match each agent's static value field
    @test all(v -> v == 7, d["vals-dict-a1"])
    @test all(v -> v == 9, d["vals-dict-a2"])
end

# ── MessageTransaction recording ──────────────────────────────────────────────

@testset "MessageTransactionRecorded" begin
    world = create_world(DateTime(0),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    sender   = register(world, RecTxSender(0))
    receiver = register(world, RecTxReceiver(0))

    activate(world) do
        send_message(sender, "hello-tx", address(receiver))
        step_simulation(world, 1.0)
    end

    @test length(world.recorded_messages) == 1
    tx = world.recorded_messages[1]
    @test tx.receiver_id == aid(receiver)
    @test tx.content == "hello-tx"
end
