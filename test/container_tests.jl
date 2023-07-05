using Mango
using Test
using Parameters

import Mango.AgentCore.handle_message

@agent struct MyAgent
    counter::Integer
end


function handle_message(agent::MyAgent, message::Any, meta::Any)
    agent.counter += 10
end


@testset "InternalContainerMessaging" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    register(container, agent1)
    register(container, agent2)

    wait(@asynclog send_message(container, "Hello Friends, this is RSc!", Dict(), agent1.aid))

    @test agent1.counter == 10
end
