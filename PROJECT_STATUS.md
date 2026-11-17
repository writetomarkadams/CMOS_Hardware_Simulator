# CMOS Hardware Simulator — Project Status

**Project:** CMOS Hardware Simulator  
**Platform:** macOS / SwiftUI / Xcode  
**Repository:** https://github.com/writetomarkadams/CMOS_Hardware_Simulator  
**Branch:** main

## 1. Project Overview

A macOS application for building and simulating electronic circuits, with an initial focus on CMOS 4000-series integrated circuits.

The application aims to provide a graphical workbench where components can be placed, connected, configured, and simulated.

## 2. Project Structure

- `CMOS4000Simulator.xcodeproj` — Xcode project
- `CMOS4000SimulatorApp.swift` — Application entry point
- `Interface/` — SwiftUI interface, workbench, symbols, and display views
- `Netlist/` — KiCad netlist and symbol parsing
- `SimulationCore/` — Logic states, nets, pins, simulation engine, and electronic components
- `CMOS4000SimulatorTests/` — Unit tests

## 3. Components in the Codebase

The following components have Swift implementation files:

| Component | Description |
|---|---|
| CD40106 | Hex Schmitt-trigger inverter |
| CD4011 | Quad NAND gate |
| CD4027 | Dual JK flip-flop |
| CD4060 | Oscillator and binary counter |
| CD4081 | Quad AND gate |
| CD4510 | BCD up/down counter |
| 1N4148 | Signal diode |
| 2N3904 | NPN transistor |
| Resistor | Passive resistor |
| SevenSegment | Seven-segment display model |

Implementation files are present; individual simulation behaviour and test coverage still need verification.

## 4. Application Features

The project includes code for:

- Graphical circuit workbench
- Component library
- Schematic symbols
- Clock source
- Logic switches and indicators
- Logic probe
- Seven-segment display
- Resistance editor
- Workbench archive
- KiCad netlist parsing

## 5. Current Development Status

- Project successfully builds and launches on the work Mac.
- Project successfully cloned, built, and launched on the home Mac.
- Private GitHub repository configured.
- Both Macs can exchange project changes through Git.

## 6. Development Workflow

Before starting work:

```bash
cd ~/Documents/GitHub/CMOS_Hardware_Simulator
git pull
```

After completing changes:

```bash
git add .
git commit -m "Describe changes"
git push
```

Always push changes before switching computers and pull before editing on the other Mac.

## 7. Next Development Tasks

- Review the current simulation engine and component implementations.
- Verify simulation behaviour and unit tests.
- Identify missing CMOS components.
- Improve the circuit workbench and wiring experience.
- Expand KiCad netlist support.
- Record known bugs and design decisions.

## 8. Current Session / Handoff Notes

**Last confirmed milestone:** Simulator builds and runs on both Macs.

**Next task:** Review the simulator's current capabilities and select the next feature or bug fix.

**Important:** GitHub synchronises project files, but not local Codex conversation history. Read this file at the start of a new development session.

## 9. Development Notes

Update this document whenever we complete a significant feature, discover an issue, or make an architectural decision.

Keep the latest development notes here so future sessions can resume without reconstructing the project's history.

