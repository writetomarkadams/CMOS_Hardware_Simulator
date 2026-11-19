# CMOS Hardware Simulator — Project Status

**Project:** CMOS Hardware Simulator  
**Platform:** macOS / SwiftUI / Xcode  
**Repository:** https://github.com/writetomarkadams/CMOS_Hardware_Simulator  
**Branch:** main  
**Last updated:** 19 November 2026  
**Project root:** /Users/mark.adams/Documents/GitHub/CMOS_Hardware_Simulator

Use this project root for all development. Leave the previous project location untouched.

## 1. Project Overview

A macOS application for building and simulating electronic circuits, with an initial focus on CMOS 4000-series integrated circuits.

The application opens directly into the Circuit Workbench. Users can place components, wire individual physical pins, configure sources and indicators, and run digital simulations. The longer-term target is a complete CMOS 12/24-hour clock.

## 2. Project Structure

- `CMOS4000Simulator.xcodeproj` — Xcode project
- `CMOS4000SimulatorApp.swift` — Application entry point
- `Interface/` — SwiftUI workbench, component library, symbols, editors, and circuit archives
- `Netlist/` — KiCad netlist and symbol parsing
- `SimulationCore/` — Logic states, nets, pins, engine, shared power validation, and components
- `CMOS4000SimulatorTests/` — Swift Testing suites, including `AdditionalCounterTests.swift`
- `SimulationCore/Components/AdditionalCounters.swift` — CD4017, CD4026, CD4516, and shared CD4518/CD4520 models

## 3. Implemented Components

| Component | Implemented behaviour |
|---|---|
| CD40106 | Six digital inverters using Schmitt-trigger symbols |
| CD4011 | Four NAND gates |
| CD4027 | Two JK flip-flops, rising-edge clocking, asynchronous SET/RESET |
| CD4060 | External-clock binary divider, falling-edge counting, asynchronous RESET |
| CD4051 | One bidirectional 8-channel switch |
| CD4052 | Two bidirectional 4-channel switches with shared selectors |
| CD4053 | Three bidirectional 2-channel switches with independent selectors |
| CD4081 | Four AND gates |
| CD4510 | BCD up/down counter, preset, RESET, Carry In/Out, cascading |
| CD4017 | Decade counter, ten decoded outputs, clock inhibit, RESET, divide-by-ten carry |
| CD4026 | Decade counter, active-HIGH segment outputs, display enable, ungated c, carry |
| CD4516 | Four-bit binary up/down counter, parallel preset, RESET, Carry In/Out |
| CD4518 | Two independent BCD counters |
| CD4520 | Two independent four-bit binary counters |
| CD4511 | BCD latch/decoder/driver, latch enable, blanking, lamp test |
| CD4543 | BCD latch/decoder/driver, latch control, blanking, phase selection |
| MAN74A | Common-cathode digit with independently wired segments and decimal point |
| MAN72A | Common-anode digit with independently wired segments and left decimal point |
| 1N4148 | Simplified digital forward-conduction model |
| 2N3904 | Simplified digital NPN low-side switch |
| R_Small | Resistor symbol, editable Ω/kΩ/MΩ value, weak digital signal transfer |

Sources and indicators include +5 V, GND, a graphical Logic Switch, a clickable 0/1 Logic Input, a numeric Clock Source, a Logic Pull-up, and a text-free LED with independently selectable red, green, orange, blue, or yellow colour.

The CD4518 and CD4520 count on a rising CLOCK with ENABLE HIGH, or a falling ENABLE with CLOCK LOW. Their units roll over at 10 and 16 respectively.

### Symbols and physical packages

- KiCad symbol directory: `/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols`.
- Datasheets determine simulation behaviour. Symbol libraries supply available drawing geometry and pin mappings.
- CD4026 and CD4516 were absent from the installed libraries. They use matching rectangular symbols with datasheet-based pinouts.
- Multi-unit placements share one underlying IC instance and package designator.
- Duplicate gate/counter units and duplicate power units within a package are prevented.
- CD4011/CD4081 use A–D logic units and E power. CD4027/CD4518/CD4520 use A/B logic units and C power. CD40106 uses A–F logic units and G power.

### Display connections

- MAN74A common-cathode pins are 4 and 12. Segments light with a LOW common and a HIGH segment input.
- MAN72A common-anode pins are 3 and 14. Segments light with a HIGH common and a LOW segment input.
- CD4543 PH LOW suits MAN74A. PH HIGH suits MAN72A.
- Displays respond to individual segment wires.

## 4. Workbench Features

- Searchable component library opened with **A**, with collapsible sections.
- Free component placement within a scrollable canvas.
- Dotted grid with snapping for component placement and wire bends.
- New components appear within the visible canvas. Crowded areas can produce overlaps.
- Click a pin to start wiring, click canvas locations for orthogonal bends, then click a pin or existing wire to finish.
- Connecting to an existing wire creates a shared electrical junction and a green junction dot.
- Click an existing wire outside wiring mode to select it.
- Right-click components or wires to remove them. Delete removes a selected wire or selected components.
- Drag empty canvas to select components.
- Selected components highlight and rotate in 90° increments with **⌘R**.
- **⌘Z / ⇧⌘Z** undo and redo additions, layout edits, completed wiring, deletion, component settings, power mode, and clearing.
- Right-click configurable components to edit resistance, clock frequency, or LED colour.
- Clock Source accepts positive numeric frequencies in Hz, kHz, or MHz, including fractional values.
- Clock edges are processed in batches at the requested rate. Pending edges are retained when processing falls behind, and the Workbench displays a slowdown warning.
- A timed 32,768 Hz → CD4060 → CD4027 check produced approximately one output cycle per second.
- CXO-DIP8 was replaced by the configurable Clock Source.
- **⌘S** saves a Workbench JSON file. **⌘O** opens it.
- Files preserve components, package identities, positions, rotations, wires, junctions, switch states, resistance values, LED colours, clock frequencies, and power mode.
- Clocks reopen paused. Archives store circuit configuration. Sequential state reinitialises when the circuit reopens.

## 5. Power and Logic Architecture

The engine supports LOW, HIGH, HIGH-Z, and UNDEFINED. UNDEFINED represents X.

### Power modes

- **Automatic Power** is the default for new circuits and assumes a 5 V supply.
- **Explicit Power** requires VDD connected to +5 V and VSS connected to GND.
- Shared power units are available in the library after placing a package's first logic unit.
- Every unit in a physical package shares its power state.
- Supply rails carry their own identity. An ordinary logic HIGH or LOW cannot substitute for a supply connection.
- Missing or incorrect supplies display an orange warning on affected units.
- Unpowered CMOS outputs drive X through the shared power-validation layer.

### CD4051/CD4052/CD4053 switching

The Workbench uses one rectangular symbol per package with all 16 physical pins, based on the [TI CD405xB datasheet](https://www.ti.com/lit/ds/symlink/cd4051b.pdf). INH HIGH opens every channel. A bank closes its selected channel only when INH is LOW and its selectors are definite. Unknown or floating controls leave the affected bank open.

Automatic Power assumes VDD at +5 V and VSS/VEE at ground. In Explicit Power, connect VDD (16) to +5 V, and VSS (8) and VEE (7) to GND. Invalid power opens every channel. A closed channel joins the two digital nets for driver resolution, including through cascaded switches. The model treats closed switches as ideal connections. Negative supplies, continuous voltages, on-resistance, leakage, and switching timing are outside the digital model.

### Power-loss lifecycle

The engine invokes the `powerDidFail()` hook when it first observes an unpowered chip. Sequential models use the hook to discard stored state and reset their edge detectors.

Implemented for:

- CD4027
- CD4017
- CD4026
- CD4516
- CD4518
- CD4520

For these models, restoring power alone does not restore the previous count or flip-flop state. A valid RESET, SET, preset, or applicable clocked operation must establish a known state. CD4027 toggle mode cannot resolve an unknown prior state.

New files save the selected power mode. Older version-1 files reopen in Explicit Power mode, with gate supply wires migrated to a separate shared power unit.

## 6. Verification and Current Milestone

The macOS Xcode build and full test suite passed on 19 November 2026 after adding CD4051, CD4052, and CD4053.

Coverage includes:

- Logic states, net resolution, gates, and clock-edge detection.
- CD4510 controls, carry behaviour, and synchronous cascading.
- CD4027 state loss, restoration with CLK already HIGH, downstream X propagation, and Automatic Power.
- Shared package allocation, power units, supply validation, Undo, and older-file migration.
- CD4511/CD4543 controls and wired seven-segment displays.
- MAN72A polarity, symbol pin mapping, CD4543 integration, and save/reopen.
- New counter rollover, inhibit/enable behaviour, preset, RESET, carry cascading, power loss, symbols, and archive integration.
- CD4051/CD4052/CD4053 selector combinations, inhibit, floating controls, two-way propagation, switch cascades, contention, weak pulls, power loss and restoration, symbol pin mapping, and Workbench save/reopen.

Live Workbench checks have verified wiring previews and bends, wire deletion, Undo/Redo shortcuts, placement after scrolling, junctions, file reopening, separate power symbols, and the CD4026 library entry and rendered symbol.

Previous project notes record successful builds and launches on both the work and home Macs. The latest features have been tested on the current development Mac; their latest home-Mac build has not been independently confirmed.

Check commit and push status before switching Macs.

## 7. Known Limitations and Next Development Tasks

- Extend power-loss invalidation to CD4510, CD4060, and the CD4511/CD4543 latches.
- Review CD4510 unknown-control handling and uncertain clock transitions as a separate stage.
- Review uncertain clock handling across other sequential models. Existing edge detection recognises definite LOW→HIGH and HIGH→LOW transitions.
- CD4060 supports an external digital clock. Its RC/crystal oscillator circuitry is not simulated.
- CD40106 uses digital inversion and does not model analog Schmitt thresholds or hysteresis.
- Resistors, diodes, and transistors use simplified digital models. Analog voltages, currents, propagation delays, leakage, and back-powering remain future work.
- Automatic supply voltage is currently fixed at 5 V.
- High requested clock rates can exceed real-time processing capacity in larger circuits.
- Add the CD4071 OR gates required by the reference clock circuit.
- Build and verify the complete 12/24-hour clock incrementally against the reference KiCad schematic.
- Expand KiCad import support. Parsing infrastructure exists, but general schematic-to-Workbench import is not complete.
- Track user-reported editing and simulation issues as circuits become more complex.

The reference schematic is `/Users/mark.adams/Downloads/24_12_hour_clock_project/24_12_hour_clock_project.kicad_sch`. Its oscillator/divider chain, six CD4510 counters, and 12/24-hour rollover logic provide an integration target.

## 8. Development Workflow

Before starting work:

```bash
cd ~/Documents/GitHub/CMOS_Hardware_Simulator
git pull
```

Check the working tree before pulling if local edits are present.

After completing changes, when committing and pushing is requested:

```bash
git add .
git commit -m "Describe changes"
git push
```

Push changes before switching computers and pull before editing on the other Mac.

## 9. Current Session / Handoff Notes

**Last confirmed milestone:** CD4051, CD4052, and CD4053 are integrated as bidirectional digital switches, with library entries, symbols, power handling, and save/open support. Full Xcode tests passed.

**Suggested next task:** Continue sequential power-loss handling with CD4510, keeping its unknown-input and clock-transition work in a clearly scoped stage.

Read this status file and inspect the current working tree when resuming development. Update the document after significant features, architectural decisions, or confirmed issues.
