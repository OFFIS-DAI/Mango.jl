
<p align="center">

![logo](docs/src/Logo_mango_ohne_sub.svg#gh-light-mode-only)
![logo](docs/src/Logo_mango_ohne_sub_white.svg#gh-dark-mode-only)

</p>

[Docs](https://offis-dai.github.io/Mango.jl/stable)
| [GitHub](https://github.com/OFFIS-DAI/Mango.jl) | [mail](mailto:mango@offis.de)

<!-- Tidyverse lifecycle badges, see https://www.tidyverse.org/lifecycle/ Uncomment or delete as needed. -->
![lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg)
[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/OFFIS-DAI/Mango.jl/blob/development/LICENSE)
[![Test Mango.jl](https://github.com/OFFIS-DAI/Mango.jl/actions/workflows/test-mango.yml/badge.svg)](https://github.com/OFFIS-DAI/Mango.jl/actions/workflows/test-mango.yml)
[![codecov](https://codecov.io/gh/OFFIS-DAI/Mango.jl/graph/badge.svg?token=JRZB5T2T2M)](https://codecov.io/gh/OFFIS-DAI/Mango.jl)

<!--
![lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-stable-green.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-retired-orange.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-archived-red.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-dormant-blue.svg) 
-->  



Mango.jl allows the user to create simple agents with little effort and in the same time offers options to structure agents with complex behaviour.

The agents agents can run in two different ways: in **real-time**, or **simulated**. In real-time, the agents will run as fast as possible and communicate as specified by the protocol ("they run as developed"). In the simulation mode, the agent system and their specified tasks will be scheduled and stepped (continous or discrete) and the communication will be simulated using articial delays. One big unique characteristic of Mango.jl is that both ways use the same agent-api, meaning you can develop, evaluate your agent system in a controlled simulated environment and then transfer it to a real-time setting without (majorly) changing the implementation of your agents, as both execution ways use the same API with different environments (and containers).

**Note:** _This project is still in an early development stage. 
We appreciate constructive feedback and suggestions for improvement._

## Features

* Container mechanism to speedup local message exchange
* Structuring complex agents with loose coupling and agent roles
* Built-in codecs
* Supports communication between agents directly via TCP and MQTT
* Built-in tasks mechanisms for proactive agent actions
* Continous and discrete stepping simulation using an external clock to rapidly run and inspect simulations designed for longer time-spans
  * Integrated communication and task simulation modules
  * Integrated environment with which the agents can interact in a common space

## Example

The following simple showcase demonstrates how you can define agents in Mango. Jl, assign them to containers and send messages via a TCP connection. For more information on the specifics and other features (e.g. MQTT, modular agent using roles, simulation, tasks), please have a look at our [Documentation](https://offis-dai.github.io/Mango.jl/stable)!

```julia
using Mango

import Mango.handle_message

# Define the agent struct using the @agent macro
@agent struct PingPongAgent
    counter::Int
end

# Define the way the PingPongAgent reacts to incoming messages
# Here it will reply to incoming "Pong"s with "Ping", and with incoming
# "Ping"s with "Pong"
function handle_message(agent::PingPongAgent, message::Any, meta::AbstractDict)
    if message == "Ping" && agent.counter < 5
        agent.counter += 1
        reply_to(agent, "Pong", meta)
    elseif message == "Pong" && agent.counter < 5
        agent.counter += 1
        reply_to(agent, "Ping", meta)
    end
end

# Create the container and add the protocol you want to use, here we use
# a plain TCP protocol and define the address of the containers
container = create_tcp_container("127.0.0.1", 5555)
container2 = create_tcp_container("127.0.0.1", 5556)

# Create the agents we defined above
ping_agent = PingPongAgent(0)
pong_agent = PingPongAgent(0)

# Registering the agents and the respective container
# We want to showcase the use of TCP so each agent need to be
# in its own container, otherwise the agents would communicate
# without any protocol (with simple function calls internally)
register(container2, ping_agent)
register(container, pong_agent)

# Start the Mango.jl system. At this point the TCP-server is created and bound
# to their addresses. After that, the runnable is executed (do ... end). at the 
# end the container and therefor the TCP server are shut down again. Using this 
# method it is not possible to forget starting or stopping containers.
activate([container, container2]) do 
    # Send the initial message from the ping_agent to initiate the communication
        send_message(ping_agent, "Ping", address(pong_agent))

    # Wait until some Pings and Pongs has been exchanged
    wait(Threads.@spawn begin
        while ping_agent.counter < 5
            sleep(1)
        end
    end)
end
```

## License
Mango.jl is developed and published under the MIT license.
<!-- travis-ci.com badge, uncomment or delete as needed, depending on whether you are using that service. -->
<!-- [![Build Status](https://travis-ci.com/mango/mango.jl.svg?branch=master)](https://travis-ci.com/mango/mango.jl) -->
<!-- Coverage badge on codecov.io, which is used by default. -->
<!-- Documentation -- uncomment or delete as needed -->
<!--
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://mango.github.io/mango.jl/stable)
[![Documentation](https://img.shields.io/badge/docs-master-blue.svg)](https://mango.github.io/mango.jl/dev)
-->
<!-- Aqua badge, see test/runtests.jl -->
<!-- [![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl) -->
