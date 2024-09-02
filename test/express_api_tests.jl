using Mango
using Test
using Logging
import Mango.handle_message
using Sockets: InetAddr

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
    express_two = add_agent_composed_of(container2, ExpressRole(0), ExpressRole(0), suggested_aid="test")

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
    @test aid(express_two) == "test"
end

@testset "TestRunTcpContainerExpressAPI" begin
    # Create agents based on roles
    express_one = agent_composed_of(ExpressRole(0), ExpressRole(0))
    express_two = agent_composed_of(ExpressRole(0), ExpressRole(0))

    run_with_tcp(2, express_one, express_two) do cl
        wait(send_message(express_one, "TestMessage", address(express_two)))
        wait(Threads.@spawn begin
            while express_two[1].counter != 1
                sleep(0.01)
            end
        end)
    end

    @test roles(express_two)[1].counter == 1
    @test roles(express_two)[2].counter == 1
    @test address(express_one).address == InetAddr("127.0.0.1", 5555)
    @test address(express_two).address == InetAddr("127.0.0.1", 5556)
    @test aid(express_two) == "agent0"
end

@testset "TestRunMQTTContainerExpressAPI" begin
    # Create agents based on roles
    express_one = agent_composed_of(ExpressRole(0), ExpressRole(0))
    express_two = agent_composed_of(ExpressRole(0), ExpressRole(0))

    agent_desc = (express_one, :topics => ["Uni"], :something => "")
    agent2_desc = (express_two, :topics => ["Uni"])
    container_list = nothing
    mqtt_not_test_here = false
    run_with_mqtt(2, agent_desc, agent2_desc, broker_port=1883) do cl
        if !cl[1].protocol.connected
            mqtt_not_test_here = true
            return
        end
        wait(send_message(express_one, "TestMessage", MQTTAddress(cl[1].protocol.broker_addr, "Uni")))
        wait(Threads.@spawn begin
            while express_two[1].counter != 1
                sleep(0.01)
            end
        end)
        container_list = cl
    end

    if mqtt_not_test_here
        return
    end
    @test roles(express_two)[1].counter == 1
    @test roles(express_two)[2].counter == 1
    @test container_list[1][1] == agent_desc[1]
    @test container_list[2][1] == agent2_desc[1]
    @test aid(express_two) == "agent0"
end