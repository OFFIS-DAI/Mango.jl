# Mango.jl

**Mango.jl** is a Julia framework for building and simulating multi-agent systems. It provides a clean, composable model for defining agents, structuring behavior with roles, wiring them together through containers, and running everything either in real time over a network or under a precise virtual clock — all with the same agent code.

---

## Features at a Glance

```@raw html
<div class="mango-feature-grid">
  <div class="mango-feature-card">
    <h4>Agents &amp; Roles</h4>
    <p>Define autonomous agents with <code>@agent</code>; compose reusable behaviors with <code>@role</code>.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Containers</h4>
    <p>Message routing with pluggable protocols — TCP and MQTT out of the box.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Simulation</h4>
    <p>Discrete-event and continuous-step simulation with a virtual clock.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Task Scheduling</h4>
    <p>Periodic, delayed, conditional, and one-shot task execution.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Topologies</h4>
    <p>Graph-based neighborhood management for structured agent communication.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Environment</h4>
    <p>Spatial environments for agent-based modeling.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Data Recording</h4>
    <p>Time-series data collection built into the simulation world.</p>
  </div>
  <div class="mango-feature-card">
    <h4>Codecs</h4>
    <p>BSON message serialization for cross-container communication.</p>
  </div>
</div>
```

---

## How It Fits Together

An agent system in Mango.jl is organized around three interlocking concepts:

- **Agents** — autonomous entities that send messages and schedule tasks, defined with `@agent`
- **Roles** — composable behavior units attached to agents, defined with `@role`; multiple roles share one agent's identity and address
- **Containers** — message routers that connect agents via a protocol; for simulation, a **World** replaces the container and advances a virtual clock step by step

Because both real-time containers and simulation worlds implement the same interface, the same agent and role code runs unchanged in production or in a simulation.

---

## Where to Start

```@raw html
<div class="mango-nav-grid">
  <a class="mango-nav-card" href="getting_started/">
    <strong>Getting Started</strong>
    <span>Install and run a first example in minutes.</span>
  </a>
  <a class="mango-nav-card" href="tutorials/ping_pong/">
    <strong>Tutorial: Ping-Pong</strong>
    <span>Step-by-step TCP walkthrough from scratch.</span>
  </a>
  <a class="mango-nav-card" href="concepts/">
    <strong>Concepts</strong>
    <span>Understand the agent/role/container design.</span>
  </a>
  <a class="mango-nav-card" href="api/">
    <strong>API Reference</strong>
    <span>Auto-generated full API documentation.</span>
  </a>
</div>
```

---

## Development Status

Mango.jl is in an early development state. The core API is stable and well-tested, but some edges may still be rough. Feedback and contributions are welcome on [GitHub](https://github.com/OFFIS-DAI/Mango.jl).

Mango.jl is developed and published under the **MIT license** by [OFFIS e.V.](https://www.offis.de)
