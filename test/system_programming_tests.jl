
using Mango
using Dates

@agent struct SystemProgrammingAgent
    got_it::Bool = false
end

@agent struct SystemInitAgent end

struct MessageSystemProgramming end

@testset "TestSystemProgrammingAPI" begin
    
    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)

    spa = register(world, SystemProgrammingAgent())
    sia = register(world, SystemInitAgent())

    behavior_in(world, on_message=MessageSystemProgramming, agent_types=SystemProgrammingAgent) do agent, message, meta
        agent.got_it = true
    end

    activate(world) do
        send_message(sia, MessageSystemProgramming(), address(spa))

        discrete_step_until(world, 1)
    end

    @test spa.got_it
end