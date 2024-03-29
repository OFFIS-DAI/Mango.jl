using Mango
using Test
using Parameters

import Mango.AgentCore.handle_message

@agent struct MyAgent
    counter::Integer
end

@role struct MyRole
    counter::Integer
    invoked::Bool
end

MyRole(counter::Integer) = MyRole(counter, false)

function handle_message(agent::MyAgent, message::Any, meta::Any)
    agent.counter += 10
end

function handle_message(role::MyRole, message::Any, meta::Any)
    role.counter += 10
end

@testset "AgentRoleMessage" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    role1 = MyRole(0)
    add(agent2, role1)
    register(container, agent1)
    register(container, agent2)

    wait(send_message(container, "Hello Roles, this is RSc!", AgentAddress(aid=agent2.aid)))

    @test agent2.role_handler.roles[1] === role1
    @test agent2.counter == 10
    @test agent2.role_handler.roles[1].counter == 10
end

function handle_specific_message(role::MyRole, message::Any, meta::Any)
    role.counter += 5
end

@testset "AgentRoleSubscribe" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    role1 = MyRole(0)
    add(agent2, role1)
    subscribe_message(role1, handle_specific_message, (msg, meta) -> typeof(msg) == String)
    register(container, agent1)
    register(container, agent2)

    wait(send_message(container, "Hello Roles, this is RSc!", AgentAddress(aid=agent2.aid)))

    @test agent2.role_handler.roles[1] === role1
    @test agent2.role_handler.roles[1].counter == 15
end

function on_send_message(
    role::MyRole,
    content::Any,
    agent_adress::AgentAddress;
    kwargs...,
)
    role.invoked = true
end

@testset "AgentRoleSendSubscribe" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    role1 = MyRole(0)
    add(agent2, role1)
    subscribe_send(role1, on_send_message)
    register(container, agent1)
    register(container, agent2)

    wait(send_message(agent2, "Hello Roles, this is RSc!", AgentAddress(aid=agent1.aid)))

    @test agent2.role_handler.roles[1] === role1
    @test agent2.role_handler.roles[1].invoked
end

@testset "AgentSendMessage" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    register(container, agent1)
    register(container, agent2)

    wait(send_message(agent1, "Hello Agents, this is RSc!", AgentAddress(aid=agent2.aid)))

    @test agent2.counter == 10
end

@testset "AgentSendMessageWithKwargs" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    register(container, agent1)
    register(container, agent2)

    wait(send_message(agent1, "Hello Agents, this is RSc!", AgentAddress(aid=agent2.aid); kw = 1, kw2 = 2))

    @test agent2.counter == 10
end

@testset "RoleSendMessage" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    role1 = MyRole(0)
    role2 = MyRole(0)
    add(agent2, role1)
    add(agent1, role2)
    register(container, agent1)
    register(container, agent2)

    wait(send_message(role2, "Hello Roles, this is RSc!", AgentAddress(aid=agent2.aid)))

    @test agent2.role_handler.roles[1] === role1
    @test agent2.counter == 10
    @test agent2.role_handler.roles[1].counter == 10
end

@testset "AgentSchedulerInstantThread" begin
    agent = MyAgent(0)
    result = 0

    schedule(agent, InstantTaskData()) do
        result = 10
    end
    stop_and_wait_for_all_tasks(agent)

    @test result == 10
end