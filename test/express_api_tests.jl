using Mango
using Test
using Logging
import Mango.handle_message


@agent struct ExpressAgent
    counter::Int
end

function handle_message(agent::ExpressAgent, content::Any, meta::Any)
    agent.counter += 1
end

@testset "TestCreateTCPContainerWithActivate" begin
    container = create_tcp_container("127.0.0.1", 5555, codec=(encode, decode))
    container2 = create_tcp_container("127.0.0.1", 5556)

    express_one = register(container, ExpressAgent(0))
    express_two = register(container2, ExpressAgent(0))

    activate([container, container2]) do
        wait(send_message(express_one, "TestMessage", address(express_two)))
        wait(Threads.@spawn begin
            while express_two.counter != 1
                sleep(0.01)
            end
        end)
    end

    @test express_two.counter == 1
end

@testset "TestCreateTCPContainerWithActivateError" begin
    container = create_tcp_container("127.0.0.1", 5555, codec=(encode, decode))
    container2 = create_tcp_container("127.0.0.1", 5556)

    express_one = register(container, ExpressAgent(0))
    express_two = register(container2, ExpressAgent(0))

    @test_logs (:error, "A nested error ocurred while running a mango simulation") min_level = Logging.Error begin
        activate([container, container2]) do
            throw("MyError")
        end
    end
end

@role struct ExpressRole
    counter::Int
end

function handle_message(role::ExpressRole, content::Any, meta::Any)
    role.counter += 1
end

@testset "TestRoleComposedAgents" begin
    container = create_tcp_container("127.0.0.1", 5555, codec=(encode, decode))
    container2 = create_tcp_container("127.0.0.1", 5556)

    express_one = add_agent_composed_of(container, ExpressRole(0), ExpressRole(0))
    express_two = add_agent_composed_of(container2, ExpressRole(0), ExpressRole(0))

    activate([container, container2]) do
        wait(send_message(express_one, "TestMessage", address(express_two)))
        wait(Threads.@spawn begin
            while roles(express_two)[1].counter != 1
                sleep(0.01)
            end
        end)
    end

    @test roles(express_two)[1].counter == 1
    @test roles(express_two)[2].counter == 1
end
