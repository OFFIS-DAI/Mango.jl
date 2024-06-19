using Mango
using Test
using Parameters
using TestItems
using Sockets: InetAddr, @ip_str

import Mango.AgentCore.handle_message

@agent struct MyAgent
    counter::Integer
    got_msg::Bool
end
MyAgent(c::Integer) = MyAgent(c, false)

@role struct MyRole
    counter::Integer
    invoked::Bool
end

MyRole(counter::Integer) = MyRole(counter, false)

function handle_message(agent::MyAgent, message::Any, meta::Any)
    agent.counter += 10
    agent.got_msg = true
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


@testset "AgentMQTTMessaging" begin
    broker_addr = InetAddr(ip"127.0.0.1", 1883)

    c1 = Container()
    p1 = MQTTProtocol("C1", broker_addr)

    c2 = Container()
    p2 = MQTTProtocol("C2", broker_addr)

    c1.protocol = p1
    c2.protocol = p2

    # topic names
    ALL_AGENTS = "all"
    NO_AGENTS = "no"
    SET_A = "set_a"
    SET_B = "set_b"

    a1 = MyAgent(0)
    a2 = MyAgent(0)

    b1 = MyAgent(0)

    # no subs agent
    b2 = MyAgent(0)

    register(c1, a1; topics=[SET_A, ALL_AGENTS])
    register(c1, a2; topics=[SET_A, ALL_AGENTS])
    register(c2, b1; topics=[SET_B, ALL_AGENTS])
    register(c2, b2; topics=[])

    reset_events() = begin 
        for a in [a1, a2, b1, b2] 
            a.got_msg = false
        end
    end

    # start listen loop
    wait(Threads.@spawn start(c1))
    wait(Threads.@spawn start(c2))

    # check loopback message on C1 --- should reach a1 and a2
    # NOTE: we sleep after send_message because handle_message logic happens on receive and there is no
    # loopback shortcut for MQTT messages like there is for TCP.
    # This means we have to wait for the message to return to us from the broker.
    wait(send_message(a1, "Test", MQTTAddress(broker_addr, SET_A)))
    timedwait(()->a1.got_msg, 0.5) 
    timedwait(()->a2.got_msg, 0.5) 
    reset_events()
    @test (a1.counter == a1.counter == 10) && (b1.counter == b2.counter == 0)

    # check SET_A message on c2
    wait(send_message(b1, "Test", MQTTAddress(broker_addr, SET_A)))
    timedwait(()->a1.got_msg, 0.5) 
    timedwait(()->a2.got_msg, 0.5) 
    reset_events()
    @test (a1.counter == a1.counter == 20) && (b1.counter == b2.counter == 0)

    # check SET_B message
    wait(send_message(a1, "Test", MQTTAddress(broker_addr, SET_B)))
    timedwait(()->b1.got_msg, 0.5) 
    reset_events()
    @test (a1.counter == a1.counter == 20) && b1.counter == 10 && b2.counter == 0

    # check ALL_AGENTS message
    wait(send_message(a1, "Test", MQTTAddress(broker_addr, NO_AGENTS)))
    # check NO_AGENTS message
    wait(send_message(a1, "Test", MQTTAddress(broker_addr, ALL_AGENTS)))

    # both conditions checked here because for no_agents we have nothing nice to wait on
    # and the resulting counts should be the same in both cases
    timedwait(()->a1.got_msg, 0.5) 
    timedwait(()->a2.got_msg, 0.5) 
    timedwait(()->b1.got_msg, 0.5) 
    reset_events()
    @test (a1.counter == a1.counter == 30) && b1.counter == 20 && b2.counter == 0

    # shutdown
    wait(Threads.@spawn shutdown(c1))
    wait(Threads.@spawn shutdown(c2))
end