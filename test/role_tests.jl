using Mango
using Test
using Parameters

import Mango.handle_event, Mango.handle_message

@agent struct RoleTestAgent
    counter::Integer
end

@role struct RoleTestRole
    counter::Integer
    src::Union{Role,Nothing}
end

struct TestEvent
end

function handle_event(role::Role, src::Role, event::TestEvent; event_type::Any)
    role.counter = 1
    role.src = src
end

@testset "RoleEmitEventSimpleHandle" begin
    agent = RoleTestAgent(0)
    role1 = RoleTestRole(0, nothing)
    role2 = RoleTestRole(0, nothing)
    add(agent, role1)
    add(agent, role2)

    emit_event(role1, TestEvent())

    @test role1.counter == 1
    @test role2.counter == 1
    @test role1.src == role1
    @test role2.src == role1
end

struct TestEvent2
    id::Int64
end

function custom_handler(role::Role, src::Role, event::Any, event_type::Any)
    role.counter += event.id
    role.src = src
end

@testset "RoleEmitEventSubHandle" begin
    agent = RoleTestAgent(0)
    role1 = RoleTestRole(0, nothing)
    role2 = RoleTestRole(0, nothing)
    add(agent, role1)
    add(agent, role2)
    subscribe_event(role1, TestEvent2, custom_handler, (src, event) -> event.id == 2)

    emit_event(role2, TestEvent2(2))
    emit_event(role2, TestEvent2(3))

    @test role1.counter == 2
    @test role1.src == role2
end

struct TestModel
    c::Int64
end
TestModel() = TestModel(42)

@testset "RoleGetModel" begin
    agent = RoleTestAgent(0)
    role1 = RoleTestRole(0, nothing)
    role2 = RoleTestRole(0, nothing)
    add(agent, role1)
    add(agent, role2)

    shared_model = get_model(role1, TestModel)
    shared_model2 = get_model(role2, TestModel)

    @test shared_model.c == 42
    @test shared_model == shared_model2
end


struct SharedTestEvent
end

@role struct SharedFieldTestRole
    @shared
    shared_event::SharedTestEvent
end

@testset "SharedFieldTestRole" begin
    agent = RoleTestAgent(0)
    role1 = SharedFieldTestRole()
    role2 = SharedFieldTestRole()
    add(agent, role1)
    add(agent, role2)

    @test !isnothing(role1.shared_event)
    @test role1.shared_event === role2.shared_event
end

struct SharedTestEvent2
end

@role struct SharedFieldsTestRole
    @shared
    shared_event::SharedTestEvent
    @shared
    shared_event2::SharedTestEvent2
end


@testset "SharedFieldsTestRole" begin
    agent = RoleTestAgent(0)
    role1 = SharedFieldsTestRole()
    role2 = SharedFieldsTestRole()
    add(agent, role1)
    add(agent, role2)

    @test !isnothing(role1.shared_event)
    @test !isnothing(role1.shared_event2)
    @test role1.shared_event2 === role2.shared_event2
    @test role1.shared_event === role2.shared_event
end


@testset "RoleSchedulerInstantThread" begin
    agent = RoleTestAgent(0)
    role1 = RoleTestRole(0, nothing)
    add(agent, role1)
    result = 0

    schedule(role1, InstantTaskData()) do
        result = 10
    end
    stop_and_wait_for_all_tasks(agent.scheduler)

    @test result == 10
end


@testset "RoleGetAddress" begin
    agent = RoleTestAgent(0)
    role1 = RoleTestRole(0, nothing)
    add(agent, role1)

    addr = address(role1)

    @test addr.aid == aid(agent)
    @test isnothing(addr.address)
end

@role struct ForwardingTestRole
    forwarded_from::AgentAddress
    forward_to::AgentAddress
    forward_is_here::Bool
end

function handle_message(role::ForwardingTestRole, content::Any, meta::Any)
    if !get(meta, "forwarded", false)
        wait(forward_to(role, content, role.forward_to, meta))
    else
        role.forward_is_here = true
        @test meta["forwarded_from_address"] == role.forwarded_from.address
        @test meta["forwarded_from_id"] == role.forwarded_from.aid
    end
end

@testset "RoleForwardMessage" begin
    container = Container()
    agent1 = RoleTestAgent(0)
    agent2 = RoleTestAgent(0)
    agent3 = RoleTestAgent(0)
    register(container, agent1)
    register(container, agent2)
    register(container, agent3)
    role1 = ForwardingTestRole(address(agent1), address(agent3), false)
    role2 = ForwardingTestRole(address(agent1), address(agent3), false)
    role3 = ForwardingTestRole(address(agent1), address(agent3), false)
    add(agent1, role1)
    add(agent2, role2)
    add(agent3, role3)

    wait(send_message(role1, "Hey, forward me!", address(role2)))

    @test role3.forward_is_here
end

@role struct AutoForwarder
end
@role struct ForwardTarget
    forward_arrived::Bool
    forwarded_from::AgentAddress
end

function handle_message(role::ForwardTarget, content::Any, meta::Any)
    role.forward_arrived = meta["forwarded"]
    role.forwarded_from = AgentAddress(aid=meta["forwarded_from_id"],
        address=meta["forwarded_from_address"])
end

@testset "RoleAutoForwardMessage" begin
    container = Container()
    agent1 = RoleTestAgent(0)
    agent2 = RoleTestAgent(0)
    agent3 = RoleTestAgent(0)
    register(container, agent1)
    register(container, agent2)
    register(container, agent3)
    role1 = AutoForwarder()
    role2 = AutoForwarder()
    role3 = ForwardTarget(false, address(agent3))
    add(agent1, role1)
    add(agent2, role2)
    add(agent3, role3)

    add_forwarding_rule(role2, address(role1), address(role3), false)
    wait(send_message(role1, "Hey, forward me!", address(role2)))

    @test role3.forward_arrived
    @test role3.forwarded_from == address(role1)
end

@role struct Replier
end

function handle_message(role::Replier, content::Any, meta::Any)
    wait(reply_to(role, "Reply!", meta))
end

@testset "RoleAutoForwardMessageWithReply" begin
    container = Container()
    agent1 = RoleTestAgent(0)
    agent2 = RoleTestAgent(0)
    agent3 = RoleTestAgent(0)
    register(container, agent1)
    register(container, agent2)
    register(container, agent3)
    role1 = ForwardTarget(false, address(agent1))
    role2 = AutoForwarder()
    role3 = ForwardTarget(false, address(agent3))
    add(agent1, role1)
    add(agent2, role2)
    add(agent3, role3)
    add(agent3, Replier())

    add_forwarding_rule(role2, address(role1), address(role3), true)
    wait(send_message(role1, "Hey, forward me!", address(role2)))

    @test role3.forward_arrived
    @test role3.forwarded_from == address(role1)
    @test role1.forward_arrived
    @test role1.forwarded_from == address(role3)

    delete_forwarding_rule(role2, address(role1), nothing)

    role3.forward_arrived = false
    role1.forward_arrived = false
    wait(send_message(role1, "Hey, forward me!", address(role2)))

    @test !role3.forward_arrived
    @test !role1.forward_arrived
end

@role struct MyRoleVar{T}
    counter::T
end

@testset "TestTypedRoles" begin
    role_var = MyRoleVar(1)
    @test role_var.counter == 1
end