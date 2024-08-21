
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

## Installation
`Mango.jl` is registered to JuliaHub.
To add it to your Julia installation or project you can use the Julia REPL by calling `]add Mango` or `import Pkg; Pkg.add("Mango")` directly:

```
> julia --project=.                                                         ✔ 
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.10.4 (2024-06-04)
 _/ |\__'_|_|_|\__'_|  |  
|__/                   |

(project_name) pkg> add Mango
    Updating registry at `~/.julia/registries/General.toml`
    [...]
```

## Example

The following simple showcase demonstrates how you can define agents in Mango. Jl, assign them to containers and send messages via a TCP connection. For more information on the specifics and other features (e.g. MQTT, modular agent using roles, simulation, tasks), please have a look at our [Documentation](https://offis-dai.github.io/Mango.jl/stable)!

```julia
using Mango
using Sockets: InetAddr, @ip_str
import Mango.handle_message

# Create the container instances with TCP protocol
container = Container()
container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 5555))

container2 = Container()
container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 5556))

# An agent in `Mango.jl` is a struct defined with the `@agent` keyword.
# We define a `TCPPingPongAgent` that has an internal counter for incoming messages.
@agent struct TCPPingPongAgent
    counter::Int
end

# Create instances of ping pong agents
ping_agent = TCPPingPongAgent(0)
pong_agent = TCPPingPongAgent(0)

# register each agent to a container and give them a name
register(container, ping_agent, "Agent_1")
register(container2, pong_agent, "Agent_2")

# When an incoming message is addressed at an agent, its container will call the `handle_message` function for it. 
# Using Julias multiple dispatch, we can define a new `handle_message` method for our agent.
function handle_message(agent::TCPPingPongAgent, message::Any, meta::Any)
    agent.counter += 1

    println(
        "$(agent.aid) got a message: $message." *
        "This is message number: $(agent.counter) for me!"
    )

    # doing very important work
    sleep(0.5)

    if message == "Ping"
        t = AgentAddress(meta["sender_id"], meta["sender_addr"], nothing)
        send_message(agent, "Pong", t)
    elseif message == "Pong"
        t = AgentAddress(meta["sender_id"], meta["sender_addr"], nothing)
        send_message(agent, "Ping", t)
    end
end

# With all this in place, we can send a message to the first agent to start the repeated message exchange.
# To do this, we need to start the containers so they listen to incoming messages and send the initating message.
# The best way to start the container message loops and ensure they are correctly shut down in the end is the
# `activate(containers)` function.
activate([container, container2]) do
    send_message(ping_agent, "Ping", address(pong_agent))

    # wait for 5 messages to have been sent
    while ping_agent.counter < 5
        sleep(1)
    end
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
