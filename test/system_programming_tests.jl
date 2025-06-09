
using Mango
using Dates

@agent struct SystemProgrammingAgent
    got_it::Bool = false
end

@role struct SystenProgrammingRole 
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

@testset "TestSystemProgrammingAPIEvent" begin
    
    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)

    spa = add_agent_composed_of(world, SystenProgrammingRole())
    sia = register(world, SystemInitAgent())

    behavior_in(world, on_event=MessageSystemProgramming, role_types=SystenProgrammingRole) do role, _,_,_
        role.got_it = true
    end

    activate(world) do
        emit_event(spa[SystenProgrammingRole], MessageSystemProgramming())

        discrete_step_until(world, 1)
    end

    @test spa[SystenProgrammingRole].got_it
end

@testset "TestSystemProgrammingAPIGlobalEvent" begin
    
    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)
    spa = register(world, SystemProgrammingAgent())
    sia = register(world, SystemInitAgent())
    
    behavior_in(world, on_global_event=MessageSystemProgramming, agent_types=SystemProgrammingAgent) do agent, global_event
        agent.got_it = true
    end
    
    activate(world) do
        emit_global_event(world.env, MessageSystemProgramming())

        discrete_step_until(world, 1)
    end

    @test spa.got_it
end

@testset "TestSystemProgrammingAPIRole" begin
    
    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)

    spa = add_agent_composed_of(world, SystenProgrammingRole())
    sia = register(world, SystemInitAgent())

    behavior_in(world, on_message=MessageSystemProgramming, role_types=SystenProgrammingRole) do role, message, meta
        role.got_it = true
    end

    activate(world) do
        send_message(sia, MessageSystemProgramming(), address(spa))

        discrete_step_until(world, 1)
    end

    @test spa[SystenProgrammingRole].got_it
end