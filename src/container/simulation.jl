export SimulationContainer, register, send_message, shutdown, protocol_addr, create_simulation_container, step_simulation, SimulationResult, CommunicationSimulationResult, TaskSimulationResult, on_step

using Base.Threads
using Dates
using ConcurrentCollections
using OrderedCollections

# id key for the receiver
RECEIVER_ID::String = "receiver_id"
# prefix for the generated aid's
AGENT_PREFIX::String = "agent"
# DISCRETE EVENT STEP SIZE
DISCRETE_EVENT::Real = -1

function create_simulation_container(start_time::DateTime; communication_sim::Union{Nothing, CommunicationSimulation} = nothing, task_sim::Union{Nothing, TaskSimulation} = nothing)
	container = SimulationContainer()
	container.clock.simulation_time = start_time
	if !isnothing(communication_sim)
		container.communication_sim = communication_sim
	end
	if !isnothing(task_sim)
		container.task_sim = task_sim
	end
	return container
end

struct MessageData
	content::Any
	meta::AbstractDict
	arriving_time::DateTime
end

@kwdef mutable struct SimulationContainer <: ContainerInterface
	world::World = World()
	clock::Clock = Clock(DateTime(0))
	task_sim::TaskSimulation = SimpleTaskSimulation(clock = clock)
	agents::Dict{String, Agent} = Dict()
	agent_counter::Integer = 0
	shutdown::Bool = false
	communication_sim::CommunicationSimulation = SimpleCommunicationSimulation()
	message_queue::ConcurrentQueue{MessageData} = ConcurrentQueue{MessageData}()
end

function on_step(agent::Agent, world::World, clock::Clock, step_size_s::Real)
	# default nothing
end

function on_step(role::Role, world::World, clock::Clock, step_size_s::Real)
	# default nothing
end

function step_agent(agent::Agent, world::World, clock::Clock, step_size_s::Real)
	on_step(agent, world, clock, step_size_s)
	for role in roles(agent)
		on_step(role, world, clock, step_size_s)
	end
end

struct MessagingIterationResult
	communication_result::CommunicationSimulationResult
	state_changed::Bool
end
@kwdef struct MessagingSimulationResult
	results::Vector{MessagingIterationResult} = Vector()
end
@kwdef struct TaskSimulationResult
	results::Vector{TaskIterationResult} = Vector()
end

struct SimulationResult
	time_elapsed::Real
	messasing_result::MessagingSimulationResult
	task_result::TaskSimulationResult
	simulation_step_size_s::Real
end

function to_message_package(message_data::MessageData)::MessagePackage
	sender_aid = message_data.meta[SENDER_ID]
	receiver_aid = message_data.meta[RECEIVER_ID]
	return MessagePackage(sender_aid, receiver_aid, message_data.arriving_time, (message_data.content, message_data.meta))
end

function to_cs_input!(message_queue::ConcurrentQueue{MessageData})::Vector{MessagePackage}
	messages_packages = Vector()
	while true
		some_message = maybepopfirst!(message_queue)
		if isnothing(some_message)
			break
		end
		message::MessageData = something(some_message)
		push!(messages_packages, to_message_package(message))
	end
	return messages_packages
end

function to_cs_input(message_queue::ConcurrentQueue{MessageData})::Vector{MessagePackage}
	messages_packages = Vector()
	next = message_queue.head.next
	while !isnothing(next)
		message::MessageData = next.value
		push!(messages_packages, to_message_package(message))
		next = next.next
	end
	return messages_packages
end


function cs_step_iteration(container::SimulationContainer,
	step_size_s::Real,
	pre_communication_result::Union{Nothing, CommunicationSimulationResult})::MessagingIterationResult
	message_packages = to_cs_input!(container.message_queue)
	communication_result = pre_communication_result
	if isnothing(communication_result)
		communication_result = calculate_communication(container.communication_sim,
			container.clock,
			message_packages)
	end
	state_changed = false
	@sync begin
		for (mp, pr) in sort([z for z in zip(message_packages, communication_result.package_results)], by = t -> add_seconds(t[1].sent_date, t[2].delay_s))
			if add_seconds(mp.sent_date, pr.delay_s) <= add_seconds(container.clock.simulation_time, step_size_s) && pr.reached
				state_changed = true
				@spawnlog process_message(container, mp.content[1], mp.content[2])
			else
				# process it later
				push!(container.message_queue, MessageData(mp.content[1], mp.content[2], mp.sent_date))
			end
		end
	end
	return MessagingIterationResult(communication_result, state_changed)
end

function determine_time_step(container::SimulationContainer)
	message_packages = to_cs_input(container.message_queue)
	communication_result = calculate_communication(container.communication_sim, container.clock, message_packages)

	# earliest message or -1 if no message arrives
	message_arrival_times = [add_seconds(t[1].sent_date, t[2].delay_s) for t in zip(message_packages, communication_result.package_results)]
	time_to_next_message_s = nothing
	if length(message_arrival_times) > 0
		time_to_next_message_s = (findmin(message_arrival_times)[1] - container.clock.simulation_time).value / 1000
	end
	@debug "Next message in $time_to_next_message_s"

	# ealiest task or -1 if no task scheduled
	next_event_s = determine_next_event_time(container.task_sim)

	@debug "Next event in $next_event_s"

	# check whether one is absent and the other is present
	if isnothing(time_to_next_message_s) && isnothing(next_event_s)
		return nothing, communication_result
	elseif isnothing(next_event_s)
		return time_to_next_message_s, communication_result
	elseif isnothing(time_to_next_message_s)
		return next_event_s, communication_result
	end

	# return earliest
	return min(time_to_next_message_s, next_event_s), communication_result
end

function step_simulation(container::SimulationContainer, step_size_s::Real = DISCRETE_EVENT)::Union{SimulationResult, Nothing}
	# Init world if uninitialized
	if !initialized(container.world)
		initialize(container.world, [v for v in values(container.agents)])
	end

	state_changed = true

	@debug "Time" container.clock

	task_sim_result = TaskSimulationResult()
	messaging_sim_result = MessagingSimulationResult()
	first_step = true
	time_step_s = step_size_s

	# We are in discrete event mode, so we need to determine
	# the time until the next event occurs, this time will
	# be used to execute the time-based simulation
	comm_result = nothing
	if time_step_s == DISCRETE_EVENT
		time_step_s, comm_result = determine_time_step(container)
		@debug "Determined the size to be $time_step_s"
		if isnothing(time_step_s)
			return nothing
		end
	end
	elapsed = @elapsed begin
		# now we process everything which happened in the steps,
		# tasks and previous iterations
		while state_changed
			@debug "Start simulation iteration"
			task_iter_result = nothing
			comm_iter_result = nothing
			@sync begin
				Threads.@spawn comm_iter_result = cs_step_iteration(container, time_step_s, first_step ? comm_result : nothing)
				Threads.@spawn task_iter_result = step_iteration(container.task_sim, time_step_s, first_step)
			end
			first_step = false
			push!(task_sim_result.results, task_iter_result)
			push!(messaging_sim_result.results, comm_iter_result)
			state_changed = comm_iter_result.state_changed || task_iter_result.state_changed
			@debug "Finish simulation iteration" state_changed
		end

		# agents act on the stepping hook
		for agent in values(container.agents)
			step_agent(agent, container.world, container.clock, time_step_s)
		end
	end
	@debug "The simulation iteration needed $elapsed seconds"

	container.clock.simulation_time = add_seconds(container.clock.simulation_time, time_step_s)

	@debug "new time", container.clock.simulation_time

	return SimulationResult(elapsed, messaging_sim_result, task_sim_result, time_step_s)
end

"""
Get protocol addr part
"""
function protocol_addr(container::SimulationContainer)
	return nothing
end

"""
Shut down the container. It is always necessary to call it for freeing bound resources
"""
function shutdown(container::SimulationContainer)
	container.shutdown = true

	for agent in values(container.agents)
		shutdown(agent)
	end
end

"""
Register an agent given the target container `container`. While registering
an aid will be generated and assigned to the agent.

This function will add the agent to the internal list of the container and will from
then on be controlled by the container regarding the messaging activities. That means
the container acts as the gateway of the agent defining its possible way to retrieve 
messages.

# Args
suggested_aid: you can provide an aid yourself. The container will always use that aid
	if possible

# Returns
The actually used aid will be returned.
"""
function register(
	container::SimulationContainer,
	agent::Agent,
	suggested_aid::Union{String, Nothing} = nothing;
	kwargs...,
)
	actual_aid::String = "$AGENT_PREFIX$(container.agent_counter)"
	if !isnothing(suggested_aid) && !haskey(container.agents, suggested_aid)
		actual_aid = suggested_aid
	end
	container.agents[actual_aid] = agent
	agent.aid = actual_aid
	agent.context = AgentContext(container)
	container.agent_counter += 1

	if !isnothing(container.task_sim)
		agent.scheduler = create_agent_scheduler(container.task_sim)
	end

	return agent
end

function process_message(container::SimulationContainer, msg::Any, meta::AbstractDict)
	receiver_id = meta[RECEIVER_ID]

	if !haskey(container.agents, meta[RECEIVER_ID])
		@warn "Container $(keys(container.agents)) has no agent with id: $receiver_id"
	else
		agent = container.agents[receiver_id]
		return dispatch_message(agent, msg, meta)
	end
end


"""
Internal function of the container, which forward the message to the correct agent in the container.
At this point it has already been evaluated the message has to be routed to an agent in control of
the container. 
"""
function forward_message(container::SimulationContainer, msg::Any, meta::AbstractDict)
	push!(container.message_queue, MessageData(msg, meta, container.clock.simulation_time))
end

"""
Send a message `message` with using the given container `container`
to the agent with the receiver id `receiver_id`. The receivers address 
is used by the chosen protocol to appropriatley route the message to
external participants. To specifiy further meta data of the message
`kwargs` should be used.

# Returns
True if the message has been sent successfully, false otherwise.
"""
function send_message(
	container::SimulationContainer,
	content::Any,
	agent_adress::AgentAddress,
	sender_id::Union{Nothing, String} = nothing;
	kwargs...,
)
	receiver_id = agent_adress.aid
	tracking_id = agent_adress.tracking_id

	meta = OrderedDict{String, Any}()
	for (key, value) in kwargs
		meta[string(key)] = value
	end

	meta[RECEIVER_ID] = receiver_id
	meta[SENDER_ID] = sender_id
	meta[TRACKING_ID] = tracking_id
	meta[SENDER_ADDR] = nothing

	return forward_message(container, content, meta)
end
