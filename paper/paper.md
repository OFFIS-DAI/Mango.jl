---
title: 'Mango.jl: A Julia-Based Multi-Agent Simulation Framework'
tags:
  - Julia
  - Multi-Agent Systems
  - Simulation Framework
authors:
  - name: Jens Sager
    orcid: 0000-0001-6352-4213
    equal-contrib: true
    affiliation: "1, 2" # (Multiple affiliations must be quoted)
  - name: Rico Schrage
      orcid: 0000-0001-5339-6553
      equal-contrib: true
      affiliation: "1, 2" # (Multiple affiliations must be quoted)

affiliations:
 - name: Digitalized Energy Systems Group, Carl von  Ossietzky Universität Oldenburg, 26129 Oldenburg, Germany
   index: 1
 - name: Energy Division, OFFIS Institute for Information Technology, 26121 Oldenburg, Germany
   index: 2
date: 31 July 2024
bibliography: paper.bib

# Optional fields if submitting to a AAS journal too, see this blog post:
# https://blog.joss.theoj.org/2018/12/a-new-collaboration-with-aas-publishing
# aas-doi: 10.3847/xxxxx <- update this with the DOI from AAS once you know it.
# aas-journal: Astrophysical Journal <- The name of the AAS journal.
---

# Summary
Multi-agent simulations are inherently complex making them difficult to implement, maintain, and optimize.
`Mango.jl` is a performance-focused framework for multi-agent systems implemented in Julia.
It enables quick implementations of multiple communicating software agents on one or more devices.

The feature scope is largely based on the existing python framework mango [@Schrage:2024].
This includes message-based communication directly via TCP or indirectly using MQTT, agent-local scheduling of tasks and abstraction of network interfaces by containers.



# Statement of need
The main difference to the python-based framework and reason for the Julia-based reimplementation is to allow better focus on simulation performance, enabling larger scales of multi-agent simulations.
This is especially relevant in the energy domain, where an increasing amount of energy resources (e.g. batteries and PV-generators) have distributed ownership, competing goals and contribute to the same power grid.
Large scale multi-agent simulations allow studying the behavior of these participants in energy markets and grid simulations.

# Acknowledgements

TBD


# References