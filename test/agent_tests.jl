using Mango
using Test
using Parameters
using TestItems

import Mango.handle_message

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



@agent struct MyRespondingAgent
    counter::Integer
    other::AgentAddress
end
@agent struct MyTrackedAgent
    counter::Integer
end

function handle_message(agent::MyRespondingAgent, message::Any, meta::Any)
    agent.counter += 10
    wait(reply_to(agent, "Hello Agents, this is DialogRespondingRico", meta))
end

function handle_response(agent::MyTrackedAgent, message::Any, meta::Any)
    agent.counter = 1337
end

@testset "AgentDialog" begin

    container = Container()
    agent1 = MyTrackedAgent(0)
    agent2 = MyRespondingAgent(0, AgentAddress(aid=agent1.aid))
    register(container, agent1)
    register(container, agent2)

    wait(send_tracked_message(agent1, "Hello Agent, this is DialogRico", AgentAddress(aid=agent2.aid); response_handler=handle_response))

    @test agent2.counter == 10
    @test agent1.counter == 1337
end


@role struct MyTrackedRole
    counter::Integer
end
@role struct MyRespondingRole
    counter::Integer
end

function handle_message(role::MyRespondingRole, message::Any, meta::Any)
    role.counter += 10
    wait(reply_to(role, "Hello Roles, this is DialogRespondingRico", meta))
end

function handle_response(role::MyTrackedRole, message::Any, meta::Any)
    role.counter = 1337
end

@testset "RoleAgentDialog" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    role1 = MyTrackedRole(0)
    role2 = MyRespondingRole(0)
    add(agent2, role1)
    add(agent1, role2)
    register(container, agent1)
    register(container, agent2)

    wait(send_tracked_message(role1, "Hello Agent, this is DialogRico", AgentAddress(aid=aid(role2)); response_handler=handle_response))

    @test role2.counter == 10
    @test role1.counter == 1337
end