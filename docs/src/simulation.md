# Simulation Container

The simulation container has the same role as the real-time container and therefore acts as communication and interaction interface to the environment. The simulation container maintains an interal simulation time and only executes tasks and delivers messages according to the requested step_sizes. It can be stepped in the continous mode or the discrete event mode. Further the container manages a common environment the agents can interact with as base structure for agent-based modeling simulations.

## Create and stepping a simulation container

To create a simulation container, it is advised to use `create_simulation_container`. This method will create a clock with the given simulation time and set default for the communication simulation and the general task simulation. In most cases the default task simulation will be what you desire. The communication simulation object (based on the abstract type `CommunicationSimulation`) is used to determine the delays of the messages in the simulation, while the task simulation determines the way the tasks are scheduled (within a time step, using parallelization etc.) in the simulation. 

In the following example a simple simulation is executed.

```@example
using Mango, Dates

# Arbitrary agent definition
@agent struct SimAgent
end

# Create a communication simulator, the simple communication simulator works with static delays between specific agents and a global default, here 0
comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
# Set the simulation time to an initial value
container = create_simulation_container(DateTime(Millisecond(10)), communication_sim=comm_sim)

# Creating agents and registering, no difference here to the real time container
agent1 = register(container, SimAgent())
agent2 = register(container, SimAgent())

# Send a message from agent2 to agent1, the message will be written to a queue instead of processed by some protocol
send_message(agent2, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))

# in this stepping call the message will be delivered and handled to/by the agent1  
# step_size=1, if no size is specified the simulation will work as discrete event simulation, executing all tasks occurring on the next event time.
stepping_result = step_simulation(container, 1)

@info stepping_result.time_elapsed
@info container.clock
```

## Discrete event vs continous stepping

Mango.jl support discrete event and continous stepping. Discrete event stepping means that no advance time is provided instead the simulation jumps to the next event time and executes every tasks, delivers every message scheduled at this next event time. For example, you set up a simultion in which three tasks are in the queue at the event times 1,1,3; then the next step would execute the first two, and the following would execute the last task (given no new tasks are created). With continous stepping the user has to provide a step_size (in seconds), which will be used to execute every task until `simulation_time + step_size` ordered by the time of the individual tasks. It is also possible to mix both styles.

```julia
# function call examples for
# continous
stepping_result = step_simulation(container, 1.23)
# and
# discrete event
stepping_result = step_simulation(container)
```

If you do not require to mix both styles and you do not want to create very specific simulations containers, you might prefer to use the express way:

```@example
using Mango, Dates

# Arbitrary agent definition
@agent struct SteppingAgent
end

# number of steps, agents..., start_time=Start time of simulation
results = run_in_simulation(1, SteppingAgent(), PrintingAgent(), start_time=DateTime(2000)) do container
    send_message(container, "MyMessageForTheSimulation", address(container[2]))
end
```

## Communication simulation

Mango.jl is generally designed to be extenable, this is also true for the usage of a communication simulator in a Mango.jl-Simulation. To use a custom communication simulator, you can simply set the keyword argument `communication_sim` to a struct of the abstract type `CommunicationSimulation`. To implement this type, you need to add a fitting method to `Mango.calculate_communication::CommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult`. This method will then be called in the simulation loop at least once and repeatedly when new messages arrive and therefore a new state has to be determined.

The default communication simulator is [SimpleCommunicationSimulation](@ref). This simulator uses a default static delay together with a dictionary containing delays per link between individual agents.

## Agent-based modeling

The simulation container can also be used for simple agent-based modeling simulations. In agent-based modeling, units (e.g. people, cars, ...) are modeled using agents and their interaction between these agents and further units in a common world/environment. To support this the simulation container provides `on_step(agent::Agent, world::World, clock::Clock, step_size_s::Real)` (also defined on `Role`). 

The `World` can contain common objects to interact with and contains a `Space` struct which can define the type of world modeled (2D/3D/Graph/...). This struct also contains the positions of all agents. Currently there is only the `Space2D` implementation with simple cartesian coordinates. 

Please note that Mango.jl focuses on agent-based control, agent-based communication and therefore currently does not provide much supporting implementations for complex agent-based modeling simulations.