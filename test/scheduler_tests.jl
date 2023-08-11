using Mango
using Test
import Dates

@testset "SchedulerInstantAsync" begin
    scheduler = Scheduler()
    result = 0

    schedule(scheduler, InstantTaskData(), ASYNC) do 
        result = 10        
    end
    wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerInstantThread" begin
    scheduler = Scheduler()
    result = 0

    schedule(scheduler, InstantTaskData(), THREAD) do 
        result = 10        
    end
    wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerInstantProcess" begin
    scheduler = Scheduler()
    result = 0

    schedule(scheduler, InstantTaskData(), PROCESS) do 
        result = 10        
    end
    wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerPeriodicThread" begin
    scheduler = Scheduler()
    result = 0

    task = schedule(scheduler, PeriodicTaskData(0.1), THREAD) do 
        result += 10
    end
    sleep(.35)
    interrupt(task)
    wait_for_all_tasks(scheduler)

    @test result == 40
end

@testset "AgentSchedulerDateTimeThread" begin
    scheduler = Scheduler()
    result = 0

    schedule(scheduler, DateTimeTaskData(Dates.now() + Dates.Second(1)), THREAD) do 
        result = 10
    end
    wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerAwaitableThread" begin
    scheduler = Scheduler()
    result = 0

    condition = Condition()
    task = schedule(scheduler, AwaitableTaskData(condition), THREAD) do 
        result = 10
    end
    yield()
    notify(condition)
    wait_for_all_tasks(scheduler)
    
    @test result == 10
end

@testset "AgentSchedulerAwaitableThread" begin
    scheduler = Scheduler()
    result = 0

    r = 0
    task = schedule(scheduler, ConditionalTaskData(()->r == 1, 0.01), THREAD) do 
        result = 10
    end
    r = 1
    wait_for_all_tasks(scheduler)
    
    @test result == 10
end