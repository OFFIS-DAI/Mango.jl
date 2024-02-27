using Mango
using Test
import Dates

@testset "AgentSchedulerInstantThread" begin
    scheduler = Scheduler()
    result = 0

    schedule(scheduler, InstantTaskData()) do
        result = 10
    end
    stop_and_wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerPeriodicThread" begin
    scheduler = Scheduler()
    result = 0

    task = schedule(scheduler, PeriodicTaskData(0.1)) do
        result += 10
    end
    sleep(1.55)
    stop_and_wait_for_all_tasks(scheduler)

    @test result == 150
end

@testset "AgentSchedulerDateTimeThread" begin
    scheduler = Scheduler()
    result = 0

    schedule(scheduler, DateTimeTaskData(Dates.now() + Dates.Second(1))) do
        result = 10
    end
    stop_and_wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerAwaitableThread" begin
    scheduler = Scheduler()
    result = 0

    condition = Condition()
    task = schedule(scheduler, AwaitableTaskData(condition)) do
        result = 10
    end
    yield()
    notify(condition)
    stop_and_wait_for_all_tasks(scheduler)

    @test result == 10
end

@testset "AgentSchedulerConditionalThread" begin
    scheduler = Scheduler()
    result = 0

    r = 0
    task = schedule(scheduler, ConditionalTaskData(() -> r == 1, 0.01)) do
        result = 10
    end
    r = 1
    stop_and_wait_for_all_tasks(scheduler)

    @test result == 10
end
