# Scheduling

## Table of Contents

1. [Introduction](#introduction)
2. [Module Overview](#module-overview)
   - [Scheduling Types](#scheduling-types)
   - [Task Data Types](#task-data-types)
3. [Scheduler](#scheduler)
4. [Functions](#functions)
   - [execute_task](#execute_task)
   - [schedule](#schedule)
   - [wait_for_all_tasks](#wait_for_all_tasks)

## 1. Introduction

Welcome to the documentation for the `Scheduling` component in Mango.jl. This utility component provides a flexible scheduler for executing predefined tasks with different scheduling types, including `ASYNC`, `THREAD`, and `PROCESS`. It offers various `TaskData` types to specify different task execution behaviors.

## 2. Module Overview

The `Scheduling` module exports several types and functions to facilitate task scheduling and execution. Let's briefly review the main components of this module.

### Scheduling Types

The module defines the following scheduling types using an `enum`:

1. `ASYNC`: The task will be scheduled asynchronously, allowing non-blocking execution.
2. `THREAD`: The task will be scheduled as a separate thread.
3. `PROCESS`: The task will be scheduled as a separate process.

### Task Data Types

The module provides different `TaskData` types, each catering to specific scheduling requirements:

1. `PeriodicTaskData`: For tasks that need to be executed periodically, it holds the time interval in seconds between task executions.
2. `InstantTaskData`: For tasks that need to be executed instantly, without any delay.
3. `DateTimeTaskData`: For tasks that need to be executed at a specific date and time.
4. `AwaitableTaskData`: For tasks that require waiting for an awaitable object to complete before execution.
5. `ConditionalTaskData`: For tasks that execute based on a specific condition at regular intervals.


### Typical usage

Typically the scheduler is used within methods from the agent. To schedule a task the function `schedule` can be used, here you have to provide the agent, which schedules the task (or the scheduler instance), and the TaskData, which defines the flow of the task. Furthermore you can decide which type of task you want to start using the scheduling types.

```julia
agent = MyAgent(0)
result = 0

schedule(agent, InstantTaskData(), THREAD) do 
    # some expensive calculation
    result = 10       
end
wait_for_all_tasks(agent)
```

## 3. Scheduler

The `Scheduler` type is an internal structure that holds a collection of tasks to be scheduled and executed. Every agent contains such a scheduler struct by default and implements methods for convenient delegation.

### Structure

```julia
struct Scheduler
    tasks::Vector{Task}
end
```

## 4. Functions 

### execute_task 

The `execute_task` function executes a task with a specific `TaskData`.

#### Signatures

```julia
execute_task(f::Function, data::PeriodicTaskData)
execute_task(f::Function, data::InstantTaskData)
execute_task(f::Function, data::DateTimeTaskData)
execute_task(f::Function, data::AwaitableTaskData)
execute_task(f::Function, data::ConditionalTaskData)
```

### schedule

The `schedule` function adds a task to the scheduler with the specified `TaskData` and scheduling type.

#### Signature

```julia
schedule(f::Function, scheduler::Union{Scheduler,Agent}, data::TaskData, scheduling_type::SchedulingType=ASYNC)
```

### wait_for_all_tasks 

The `wait_for_all_tasks` function waits for all the scheduled tasks in the provided scheduler to complete.

#### Signature

```julia
wait_for_all_tasks(scheduler::Scheduler)
```
