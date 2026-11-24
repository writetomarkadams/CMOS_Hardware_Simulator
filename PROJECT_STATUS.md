# CMOS Hardware Simulator — Project Status

**Project:** CMOS Hardware Simulator  
**Platform:** macOS / SwiftUI / Xcode  
**Repository:** https://github.com/writetomarkadams/CMOS_Hardware_Simulator  
**Branch:** main  
**Last updated:** 24 November 2026\
**Project root:** /Users/mark.adams/Documents/GitHub/CMOS_Hardware_Simulator

Use this project root for all development. Leave the previous project location untouched.

## 1. Project Overview

A macOS application for building and simulating electronic circuits, with an initial focus on CMOS 4000-series integrated circuits.

The application opens directly into the Circuit Workbench. Users can place components, wire individual physical pins, configure sources and indicators, and run digital simulations. The longer-term target is a complete CMOS 12/24-hour clock.

### Workbench files and unsaved changes

- On 24 November 2026, the full macOS Xcode suite passed 171 tests (191 executions), with zero failures or skips. Regression coverage includes mode round-trips and legacy defaults, clipboard wiring, pin alignment and cursor-centred zoom. The native Save and Open dialogs restored Physical DIP in a fresh window.

- The macOS edited-window indicator reflects persisted circuit edits, including placement, wiring, component values, input-switch settings, power mode, component appearance and scope probe assignments. Undo and Redo track the last saved revision. Simulation state, scope captures and viewport changes do not mark a circuit edited.
- Closing a workbench window, quitting, clearing, opening another archive or replacing the circuit from a KiCad preview prompts to Save, Don’t Save or Cancel when the circuit has unsaved edits. Cancelling the prompt or a Save As panel, or failing to write the file, stops the requested action. Quit checks each workbench window.
- Save writes to the current JSON archive. Untitled circuits open a native Save As panel, and File → Save As… can choose a new destination for a named circuit. Clear starts a clean untitled workbench. A KiCad replacement starts an edited untitled workbench. Adding an import to the current circuit counts as an edit.
- On 21 November 2026, all 118 macOS Xcode tests passed. Native checks covered window close via ⌘W, quit with multiple workbench windows, Save As cancellation, save before clear, reopening the saved archive, and cancelling or confirming a KiCad replacement.

### Workbench layout and navigation

- The dotted canvas fills the workbench between two 40-point icon strips. The left strip offers Select (V), Wire (W), Add Part (A), Rotate, Zoom and Fit. Pin clicks start wires by default. Select mode cancels an unfinished wire and reserves canvas actions for selection. The right strip opens the Wire List and Oscilloscope, which are also available under View. The top bar keeps labelled Open, Save and Import buttons, and the bottom strip shows wiring hints, zoom, simulation status and power mode. The native menus retain the existing commands and shortcuts.
- Open **View → Wire List** to show the optional right sidebar. It remembers its visibility and supports selecting a wire or removing it from its context menu.
- Zoom spans 25–400%. The default KiCad navigation uses vertical scroll to zoom around the pointer and horizontal scroll to pan. Choose macOS navigation in Settings to pan with scroll and zoom with Command-scroll. Both styles support pinch to zoom, middle-button drag and Space-drag to pan. Use Fit Circuit (⌘9) in the left strip or click the zoom percentage to reset to 100% (⌘0). Fit uses the rendered component bounds, wire paths and schematic annotations. The viewport is independent of the circuit archive.

- On 20 November 2026 the full macOS suite passed all 117 case executions, including new viewport tests for cursor anchoring, zoom limits and fit. Native checks covered save/reopen, wiring, snapped part dragging at 400%, marquee selection, scroll panning, and reopening and docking a frozen scope with a probe attached. Physical trackpad pinch and moving the window between displays were not exercised.

### Workbench selection and duplication

- Click a component body to select it, Shift-click to toggle it, or drag a marquee from empty canvas. Use Space-drag or middle-button drag to pan the viewport. While a wire is in progress, empty-canvas clicks place waypoints and marquee selection is suspended. Logic switches and clock controls still operate on an ordinary click. Shift-click selects them without changing their output or run state.
- Drag any selected component to move the group by one grid-snapped offset. Internal wire bends and junctions travel with the group. Boundary wires keep their electrical endpoints and remaining waypoints, with orthogonal leads recalculated as the group moves. Crossings do not join nets.
- On the focused canvas, ⌘C copies the selection, ⌘V previews a paste, and ⌘D previews a duplicate. Click to place the preview on the grid, or press Escape to cancel. The clipboard captures component configuration and the connections between copied pins. It retains junction routes wholly inside the selection and trims branches to unselected parts. The preview uses outlines and visible wire routes. Each placement gets new part and junction IDs and the first free reference number per prefix, including when KiCad references already occupy that prefix. Multiple copied units of a chip share a fresh package.
- Delete removes the selection. A group move, paste, duplicate or delete is one Undo/Redo step. Archives retain copied settings, references and wiring. Separate KiCad schematic annotations stay at their source coordinates. Automatic boundary routes can overlap nearby wires or parts in dense layouts.

- The macOS Xcode suite passed all 121 tests. New cases cover grid-snapped group movement with a boundary wire, electrical independence at overlapping geometry, imported reference allocation, shared chip units, archive round-trip and Undo/Redo. Native checks covered Shift-click, marquee, group dragging, copy and paste placement, duplicate, Escape, and group Delete/Undo.

### Check Circuit

- Click **Check Circuit** to open a panel of findings. Each finding names the affected pin or wire, shows its current logic state, and suggests a change. Click it to center and highlight the pin or wire in orange. Checks and highlights leave the circuit, running simulation, and undo history untouched.
- Findings refresh after circuit edits. Use **Refresh Check** to reassess conditions that changed while the simulation was running. The built-in rules cover explicit supplies, display common pins, directly conflicting strong drivers, supported NE555 timing warnings, and CD4026 controls and clock input. A CD4026-to-common-cathode segment mismatch is suggested when at least four distinct matching segment nets identify a unique driver. A separate notice reports when the simulation did not settle.
- These checks cover known conditions in the simulator. They do not validate every component's control logic or infer arbitrary design intent. The macOS suite passed 123 tests, including reproduction and correction of the CD4026/display faults and read-only verification. Native checks confirmed opening the panel and clicking findings to highlight a pin and a wire.

### Workbench wire routing

- While wiring, click empty canvas to place grid-snapped waypoints. Click a pin or a clear wire segment to finish. If separate wires overlap at the click, choose a segment clear of the overlap to specify which wire to join.
- Electrical pin endpoints share the Workbench’s ten-unit grid. Library symbols use 50 mil per grid step, with body artwork and pin leads positioned around the model endpoints. The CD4510 pin order and all six CD40106 inverter pairs were checked against the KiCad reference and Texas Instruments pinouts.
- Open circles indicate unwired pins. An actual wire or hidden schematic net attachment removes the circle, and disconnecting restores it. A crossing alone leaves the circle visible. Imported explicit no-connect markers use an X until the pin is wired. Hovering in Wire mode highlights the pin with an outline and snaps the wire preview to it.
- New and generated routes use horizontal and vertical grid lanes. Wires, pin hit targets and junctions follow the same model coordinates through pan, zoom, drag and quarter-turn rotation. Older archives retain their wire waypoints and embedded artwork scale, so they can show short orthogonal leads between legacy off-grid route points and newly aligned pins.
- Moving or rotating a part changes the route to its pin while keeping the same electrical endpoint. Imported direct pin contacts become visible leads when separated. Older archives can recover a direct contact if the pin and junction still coincide when opened. Previously separated contacts in older files remain electrically connected as hidden links.
- Junction dots follow the current branches. Crossing lines, bends and overlaps alone have no electrical effect. Automatic routing can still overlap wires or pass through parts, so manual waypoints may be needed to clarify a dense drawing.

### Workbench component appearance

- **View → Component Appearance** switches the current window between **Schematic** and **Physical DIP**. New workbench windows start in Schematic. Saving a circuit stores its appearance in the archive. Older archives without that setting open in Schematic. Changing appearance marks the document edited and supports Undo and Redo while preserving live nets and scope acquisition. Pasting uses the destination workbench’s appearance.
- Add **CD4070** from **Chips** to place all four XOR gates and both supply pins in one part. In Physical DIP, the CD4070 has a cream body with a bold rounded black outline, a top notch and a pin-1 dot. The designation sits near the top, and each internal pin label aligns with its numbered tab. Inputs are green, outputs blue, and supply pins red. Pin order is 1–7 down the left and 14–8 down the right. In Schematic, the complete package shows separate XOR symbols U…A–D and the shared power unit U…E. Their pins retain the same wire and probe attachments when the appearance changes. Choose **CD4070 XOR Gate** to place individual schematic units the same way as for CD4071. The existing NE555 also supports the DIP renderer with its eight-pin layout. Imported drawings, separately placed chip units and other library parts keep their schematic appearance.
- Both views use the same rotation pivot, electrical terminal IDs, stored wire waypoints and junctions. Displayed wire paths follow the active pin coordinates, including at quarter-turn rotations. Scope probes keep their electrical attachments. As with schematic routing, an automatic route can cross nearby artwork or wires without creating an electrical connection.
- On 22 November 2026, the macOS Xcode suite passed all 141 tests after the CD4070 artwork correction. Coverage includes CD4070 pin order and XOR behaviour, grid-aligned DIP endpoints across four rotations, orthogonal wiring, live net and probe identity, archive reopen, and new and existing wire colours. The rebuilt native workbench displayed the schematic symbol with the green drawing default and the physical package with the black drawing default. The user approved the physical CD4070 screenshot on 22 November 2026. It is the visual reference for future physical DIP artwork.

- **CD4510** now uses the approved CD4070 artwork in Physical DIP. Pins 1-8 run down the left and 16-9 down the right. The body matches the CD4070 width. The carry pins use active-low overbars, and pin 10 is labelled U/D. Labels and colours use the existing component pins, verified against the [TI CD4510B datasheet](https://www.ti.com/lit/ds/symlink/cd4510b.pdf). The macOS suite passed all 143 tests on 22 November 2026, including pin order, grid alignment, connected movement and rotation, scope probe attachment, and counting through physical pins. The CD4510 screenshot is ready for review.

- **CD4511** uses the 16-pin DIP artwork in Physical DIP and retains its schematic symbol in Schematic. The decoder's wired segment outputs continue to drive the display across appearance changes and archive reopen.
- **MAN74A** uses a labelled seven-segment schematic symbol with segment pins on the left and common cathodes below. Physical DIP shows a dark red display face. **MAN72A** uses a labelled common-anode schematic symbol and a dark physical face with red segments. Segment illumination follows the wired segment and common-pin states.

### Workbench wire colours

- The wiring strip palette offers Black, Grey, Brown, Red, Orange, Yellow, Green, Blue and Violet in that order. New hand-drawn wires default to Green in Schematic and Black in Physical DIP. The palette remembers a chosen drawing colour per appearance within the window. Archives without wire colour and generated KiCad wires use Green.
- Click a wire segment or select a wire in the Wire List, then use the same palette to recolour that wire. Right-click a wire segment or Wire List entry and choose **Wire Colour** to recolour it directly. Clear the selection to return to the new-wire colour. The drawing preview follows the new-wire colour. Junction dots use canvas foreground contrast, selection uses an accent outline, and Yellow has a dark edge for visibility.
- Circuit JSON stores each wire colour. Colours persist through moves, rerouting, duplication, and Undo/Redo. When a new branch splits an existing wire, the two existing pieces keep their colour and the branch uses the drawing colour. Recolouring and its Undo/Redo preserve net identity, running signals, probe assignments and scope history.
- On 22 November 2026, all 138 macOS Xcode tests passed, including legacy archive decoding, colour save/reopen, split and move, and live scope continuity during recolouring. Native checks confirmed the palette and swatch, drawing in Yellow, recolouring a selected wire Grey, and junction contrast on the light canvas.

### LED_D3.0mm

- Add **LED_D3.0mm** from **Sources and Indicators**. The two-pin red LED uses cathode on pin 1 and anode on pin 2. Wire the anode to a driver through a current-limiting resistor and the cathode to GND for an active-HIGH indicator.
- The supported DC model uses a nominal 1.8 V forward knee and 20 Ω slope resistance. The symbol glows for forward current in supported DC networks. Colour, thermal effects, and reverse breakdown are outside this model.
- KiCad import accepts `Device:LED` with the exact `LED_THT:LED_D3.0mm` footprint. The regular Logic LED remains available as a separate one-pin indicator.

### CXO_DIP8 crystal oscillator

- Add **CXO_DIP8** from **Sources and Indicators**. Right-click the symbol, choose **Set Frequency…**, enter a positive value and select **kHz** or **MHz**. The default is 1 MHz. The symbol displays the current setting, which persists through Save/Open, Undo/Redo and duplication.
- Pin 1 is EN, pin 4 is GND, pin 5 is OUT and pin 8 is VCC. With valid power, EN HIGH or open runs the oscillator automatically. EN LOW makes OUT high impedance. In Explicit Power, wire VCC to +5 V and GND to ground.
- The oscillator is an ideal 50% duty-cycle digital source. At high frequencies the simulator can show **Clock behind** and advance more slowly than wall-clock time. The configured frequency is applied in simulated time. KiCad import for CXO_DIP8 is outside this change.

### Workbench oscilloscope

- Open **View → Oscilloscope** or use the waveform button in the right strip. The separate resizable window can move between displays. Use **Dock in Workbench** to attach it below the canvas at a fixed height, or **Undock** to return it to a window.
- Select **Probe** (eyedropper) in the drawing toolbar and click a pin, junction or clearly identifiable wire. The workbench highlights the connected net on hover, assigns the lowest free channel from CH1 to CH4, and returns to Select. The status bar shows channel occupancy. Multiple probes can share one net.
- Click a numbered marker to move that channel, or right-click it to remove the probe. Moving keeps the channel number. When all four channels are occupied, the toolbar directs you to the existing markers. The original four channel menus are also available.
- Probes sample settled net values without adding connectivity. The marker follows its pin, junction or relative position along a wire route through pan, zoom and layout edits. A wire split preserves the attachment on the appropriate branch. If its wire is removed, the marker follows an endpoint on a single identifiable surviving net. It disconnects if the net disappears or splits ambiguously. Where separate wires overlap, choose a clear stretch.
- The workbench owns acquisition even while the scope window is closed. Reopening or docking preserves the capture and display settings during the session. Probe placements support Undo/Redo and persist in circuit archives. Older archives retain their existing probes, and archives without probes open with empty channels.
- The time window ranges from 1 ms to 60 s. Digital lanes use logic levels and distinguish X and Z. Probes on a supported NE555 capacitor timing node show sampled voltage with a selectable 0–2 V, 0–5 V or 0–10 V range.
- Freeze pauses acquisition while the circuit keeps running. Run starts a fresh acquisition. Clear discards the displayed history. The time window scrolls continuously during acquisition.
- Turn on **Cursors** and drag handles **A** and **B** across the shared time axis. Read each simulation timestamp, the absolute separation **Δt**, and **1/Δt**. Coincident cursors show an undefined reciprocal. The reciprocal equals waveform frequency when the handles span exactly one full period.
- The cursors stay at their positions within the visible window as it scrolls or resizes. Freeze holds the timestamps while you line up the handles with a trace. Changing the time window rescales the measured interval. Cursor settings follow the scope when docked or undocked during the session. Placement is manual.
- The full macOS Xcode suite passed with three new cursor tests covering timestamp mapping across widths, drag limits, all four channels, time-window changes, Freeze/Run, and coincident cursors. Native checks covered both handles, crossing and aligning them, docking, and changing the frozen time window.
- Acquisition records settled scheduled clock edges and NE555 integration points in separate 8,192-entry channel buffers. The plot redraws at up to 30 FPS and groups overlapping digital edges by screen column. Dense activity appears as a band, and sustained high event rates shorten the time retained in each buffer. The scope sees simulation events and settled states, with no visibility into physical glitches or propagation delays between them.
- Analogue traces can show the recognised ideal NE555 timing node and DC operating-point voltages in supported discrete networks. The display connects integration samples with straight lines. Fast changes between samples, including ideal monostable discharge, may appear rounded or be undersampled.
- The full macOS Xcode test suite passed with the scope enabled. New tests cover buffer wraparound and visible windows, clock-edge capture between redraws, continuous scrolling and manual freeze, probe lifecycle and archive round-trip, and NE555 timing-node voltage and edge timestamps.

### KiCad netlist import

- Choose **Import Circuit…** and select a native KiCad S-expression netlist. The preview lists component references and values, electrical nets and physical pins, and warnings for omitted parts or endpoints, invalid values and possible floating connections.
- **Replace Workbench** uses Explicit Power. **Add to Workbench** places an electrically separate circuit below the existing one, retaining its power mode. Both actions support Undo and Redo. Imported package units share a physical simulator component. Wired net names, imported references, component values and placement survive Save/Open.
- Import uses the standard library symbol identity and physical pin numbers. Unknown/custom symbols, invalid values and parts with unsupported connected pin numbers are omitted after preview. Resistor and capacitor values accept decimal or scientific notation and SI markings such as `4k7`, `100nF` and `2.2 µF`. Import adds the simulator's two supported rails for uniquely named global `+5V` and `GND` nets. Other names retain their connectivity and can be wired to supplies manually.
- Initial grid placement and orthogonal routing are editable with the workbench's existing layout and wiring controls. Complex nets can cross or overlap visually. Circuit connectivity is based on wire endpoints and junctions. KiCad XML, schematic images, oscillator modules and other generic two-pin LED footprints are outside this stage.

### Native KiCad schematic import

- Choose **Import Circuit…** and open a modern single-sheet `.kicad_sch`. The existing preview lists mapped parts, physical pins, nets and omissions before Add or Replace changes the workbench. Both options support Undo and Redo. The existing KiCad netlist path still uses grid placement and automatic routing.
- The importer reads embedded symbol definitions and uses the reference, value, unit, physical pin positions, rotation and mirror from the file. It resolves source connectivity before translating, uniformly scaling and projecting pin endpoints, wire vertices, junctions and annotations onto the Workbench grid. Orthogonal wire segments retain their source direction. Off-grid source geometry can shift slightly or visually overlap after projection. For diagonal source segments, the parser resolves the source connectivity first, then the preview warns that the drawing will use right-angle bends. Converted lines can overlap or cross other lines visually. Electrical connections use the original endpoints, junctions and label links. The importer distinguishes shared endpoints, explicit junctions and label attachments from crossings. Matching single-sheet label names join nets electrically across the page.
- The existing symbol allowlist and value parsers map supported CMOS devices, discrete parts, NE555, MAN74A/MAN72A and compatible 2-, 3- and 8-pin headers. Unknown parts, incompatible units and invalid values are reported. Only placed units are shown, and units of one package share a simulator component. Standard `power:+5V` and `power:GND` symbols supply their nets at their original locations. Other power symbols can name nets without driving them.
- Imported components, wires, and simulator values are editable. Workbench JSON stores embedded graphics, rotations, reference/value fields, routes, label links, and no-connect markers. Scope channels can probe a supported physical pin or visible wire using the existing scope controls. Labels and sheet markers are source annotations and stay at their imported coordinates. Rename and re-export operations for KiCad files are outside this import workflow.
- Hierarchical sheets and labels, buses, hidden implicit power connections, simulation-excluded parts and unsupported graphics are reported. Artwork and fonts use the Workbench renderer. Simulation continues to follow the simulator’s existing digital and NE555 models.
- The local `Display_Module.kicad_sch` acceptance case imports all nine parts. Its 15 connected pin groups matched KiCad’s exported netlist. MAN74A pins 4 and 12 share the net on J1 pin 8, with no ground source in the file. Pin 9 retains its explicit no-connect marker. Tests cover split and unmarked crossings, explicit junctions, label-linked nets, mirrored and rotated pins, unsupported inputs, scope probes, archive round-trip, and netlist regression. The canonical macOS Xcode suite passed all 96 tests on 20 November 2026. Native checks confirmed preview, import, Save, Open, and attaching an oscilloscope probe to MAN74A pin 12 after reopening.

## 2. Project Structure

- `CMOS4000Simulator.xcodeproj` — Xcode project
- `CMOS4000SimulatorApp.swift` — Application entry point
- `Interface/` — SwiftUI workbench, component library, symbols, editors, and circuit archives
- `Netlist/` — KiCad netlist, schematic and symbol parsing
- `SimulationCore/` — Logic states, nets, pins, engine, shared power validation, and components
- `CMOS4000SimulatorTests/` — Swift Testing suites, including `AdditionalCounterTests.swift`
- `SimulationCore/NE555Timing.swift` — Standard NE555 RC topology recognition and exact exponential timing
- `SimulationCore/Components/AdditionalCounters.swift` — CD4017, CD4026, CD4029, CD4516, and shared CD4518/CD4520 models

## 3. Implemented Components

| Component | Implemented behaviour |
|---|---|
| NE555 | Digital latch plus ideal RC astable/monostable timing, active-LOW RESET, open-collector DISCH |
| C_Polarized | Polarized capacitor, editable µF value; pin 1 positive / pin 2 negative |
| C_Small | Non-polarized capacitor, editable nF value |
| CD40106 | Six digital inverters using Schmitt-trigger symbols |
| CD4011 | Four NAND gates |
| CD4027 | Two JK flip-flops, rising-edge clocking, asynchronous SET/RESET |
| CD4060 | External-clock binary divider, falling-edge counting, asynchronous RESET |
| CD4051 | One bidirectional 8-channel switch |
| CD4052 | Two bidirectional 4-channel switches with shared selectors |
| CD4053 | Three bidirectional 2-channel switches with independent selectors |
| CD4081 | Four AND gates |
| CD4071 | Four two-input OR gates, with four-state logic and shared power |
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

The component library includes single-row vertical 2.54 mm pin headers with 2, 3, or 8 independent contacts. KiCad import recognizes matching footprints on the corresponding `Connector:Conn_01xNN_Pin` or `Connector_Generic:Conn_01xNN` schematic symbols.

Sources and indicators include +5 V, GND, a graphical Logic Switch, a clickable 0/1 Logic Input, a numeric Clock Source, a Logic Pull-up, and a text-free LED with independently selectable red, green, orange, blue, or yellow colour.

The CD4518 and CD4520 count on a rising CLOCK with ENABLE HIGH, or a falling ENABLE with CLOCK LOW. Their units roll over at 10 and 16 respectively.

### Symbols and physical packages

- KiCad symbol directory: `/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols`.
- Datasheets determine simulation behaviour. Symbol libraries supply available drawing geometry and pin mappings.
- CD4026 and CD4516 were absent from the installed libraries. They use matching rectangular symbols with datasheet-based pinouts.
- Multi-unit placements share one underlying IC instance and package designator.
- Duplicate gate/counter units and duplicate power units within a package are prevented.
- CD4011/CD4071/CD4081 use A–D logic units and E power. CD4027/CD4518/CD4520 use A/B logic units and C power. CD40106 uses A–F logic units and G power.

### CD4029 presettable counter

- Add **CD4029** from the Counters library. In Explicit Power mode, connect pin 16 to +5 V and pin 8 to GND. An asserted PRESET ENABLE (1) loads JAM1–JAM4 (4, 12, 13, 3) into Q1–Q4 (6, 11, 14, 2). To initialize at zero, drive all JAM inputs LOW and assert PRESET ENABLE.
- Release PRESET ENABLE LOW to count on a rising CLOCK (15) with CARRY IN (5) held LOW. BINARY/DECADE (9) selects binary on HIGH and decade on LOW. UP/DOWN (10) selects up on HIGH and down on LOW. CARRY OUT (7) is LOW at the terminal count with CARRY IN LOW. For synchronous cascading, connect CARRY OUT to the next stage’s CARRY IN and share the clock.
- A preset can load any four-bit pattern. Clocking from a value above nine in decade mode produces X in the simulator. Workbench Save/Open retains the device and wiring. KiCad import accepts `4xxx:4029` and `4xxx_IEEE:4029` using physical pin numbers. [TI CD4029B datasheet](https://www.ti.com/lit/ds/symlink/cd4029b.pdf)

### Display connections

- MAN74A common-cathode pins are 4 and 12. Segments light with a LOW common and a HIGH segment input.
- MAN72A common-anode pins are 3 and 14. Segments light with a HIGH common and a LOW segment input.
- CD4543 PH LOW suits MAN74A. PH HIGH suits MAN72A.
- Displays respond to individual segment wires.

## 4. Workbench Features

- Searchable component library opened with **A**, with collapsible sections.
- Free component placement within a zoomable, pannable canvas.
- Dotted grid with snapping for component placement and wire bends.
- New components appear within the visible canvas. Crowded areas can produce overlaps.
- In Wire mode, click a pin to start, click the canvas to add snapped waypoints, and click a pin or existing wire to finish. The preview and completed route use horizontal and vertical segments and follow live pin positions during move, rotation, zoom and pan. Press **Esc** or click **Cancel** to discard the unfinished wire and its bends.
- Connecting to an existing wire creates a shared electrical junction and a green junction dot.
- Click an existing wire with no wire in progress to select it. The optional **Wire List** sidebar also supports wire selection and removal.
- Right-click components or wires to remove them. Delete removes a selected wire or selected components.
- Drag empty canvas to select components.
- Selected components highlight and rotate in 90° increments with **⌘R**.
- **⌘Z / ⇧⌘Z** undo and redo additions, layout edits, completed wiring, deletion, component settings, power mode, and clearing.
- Right-click configurable components to edit resistance, clock frequency, or LED colour.
- Clock Source accepts positive numeric frequencies in Hz, kHz, or MHz, including fractional values.
- Clock edges are processed in batches at the requested rate. Pending edges are retained when processing falls behind, and the Workbench displays a slowdown warning.
- A timed 32,768 Hz → CD4060 → CD4027 check produced approximately one output cycle per second.
- CXO-DIP8 was replaced by the configurable Clock Source.
- Labelled Open and Save buttons remain in the file bar. File menu commands act on the focused Workbench window and are disabled while its library, value editor, or file dialog is open.
- **File → Save… (⌘S)** saves a Workbench JSON file. **File → Open… (⌘O)** opens it. The Open picker also accepts older Workbench files with a non-JSON extension; file contents are validated before replacing the circuit.
- Files preserve components, package identities, positions, rotations, wires, junctions, switch states, resistance values, LED colours, clock frequencies, power mode, and component appearance.
- Manual Clock Source components reopen paused. Recognised, powered NE555 RC circuits start automatically when reopened. Archives store circuit configuration, not capacitor voltage or running sequential state.

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
- CD4029
- CD4017
- CD4026
- CD4516
- CD4518
- CD4520

For these models, restoring power alone does not restore the previous count or flip-flop state. A valid RESET, SET, preset, or applicable clocked operation must establish a known state. CD4027 toggle mode cannot resolve an unknown prior state.

New files save the selected power mode. Older version-1 files reopen in Explicit Power mode, with gate supply wires migrated to a separate shared power unit.

### NE555 RC timing and capacitor values

- C_Polarized preserves the KiCad + marker, outlined positive plate and filled negative plate. Imported fill metadata follows the symbol when rotated. The rendering correction passed the full macOS Xcode suite.
- Add C_Polarized (default 10 µF) or C_Small (default 100 nF) from Discrete Components. Right-click → Set Capacitance… opens a text field in the component's fixed unit. Positive finite fractional values are accepted; zero, negative, non-finite and underflowing values are rejected. Values, kinds, wires, positions and rotations survive save/open; value edits support Undo/Redo.
- Standard astable wiring: RA from +5 V to DISCH (7), RB from DISCH to joined TRIG/THRES (2/6), and the timing capacitor from 2/6 to GND. For C_Polarized use pin 1 at 2/6 and pin 2 at GND. Connect RESET (4) HIGH. In Explicit Power mode also wire VCC (8) to +5 V and GND (1) to GND.
- Two-diode astable wiring: connect +5 V through 10 kΩ to the joined 1N4148 anodes. Connect one cathode to DISCH (7) and the other to the joined TRIG/THRES and timing capacitor. Place 100 kΩ across the diode to TRIG/THRES. The simulator uses a nominal 0.60 V forward knee and 50 Ω slope. Supported resistor ratios keep the charging diode conducting through the upper comparator threshold.
- Standard monostable wiring: join THRES/DISCH (6/7), connect R from +5 V to that node and C from that node to GND, and drive TRIG (2) externally. Assert RESET LOW once to establish a known idle state, then release it HIGH before triggering.
- Ideal 5 V RC integration uses the capacitor's exponential voltage and 1/3 and 2/3 supply thresholds. Steady-state astable HIGH time is ln(2)(RA+RB)C and LOW time ln(2)RB*C. Startup from a discharged capacitor has a longer first HIGH pulse: ln(3)(RA+RB)C. Monostable pulse width is ln(3)RC, assuming TRIG is released before timeout. Source: [TI NE555 datasheet](https://www.ti.com/lit/ds/symlink/ne555.pdf).
- Example tested: RA=10 kΩ, RB=20 kΩ, C=10 µF → startup HIGH ≈329.584 ms, steady HIGH ≈207.944 ms, LOW ≈138.629 ms, frequency ≈2.885 Hz. Monostable R=10 kΩ and C=10 µF gives ≈109.861 ms.
- The timing solver is separate from chip logic and shared power validation. It recognises the actual nets and R/C values, suppresses the legacy digital weak-drive resistor model only within a recognised timing network, and supplies comparator inputs to NE555. Every output edge settles downstream digital components, including edges between screen updates.
- Time advances in bounded batches alongside manual clock sources. Unprocessed time remains pending; the existing slowdown indicator reports when processing falls behind. No output pulses are deliberately skipped.

### Discrete diode and transistor DC model

- Mixed circuits containing 1N4148 diodes, 2N3904 grounded-emitter stages and resistors can resolve a DC operating point. The model balances resistor and junction currents and approximates transistor gain and saturation. Logic sources are ideal 0 V/5 V. The digital LED reports HIGH at or above 2.0 V, LOW at or below 0.8 V, and X between those thresholds.
- The reference two-input diode AND with two transistor stages and 10 kΩ resistors lights the LED only when both inputs are HIGH. Scope probes on supported nodes show the DC voltage.
- The model is limited to small (up to 32 nodes), resistively referenced regions with supported ideal drivers. It leaves other discrete circuits on the existing digital models. Diode and transistor parameters are nominal approximations. Transient capacitance, switching delays, and device variation are outside this model.

## 6. Verification and Current Milestone

On 21 November 2026 the macOS build and full Xcode suite passed with the grid-aligned pin geometry. Added coverage checks the library’s pin identity and grid positions through all four rotations, the CD4510 and CD40106 pin mapping, zoomed hit targets from 25–400%, crossing and marker visibility, imported mirrored pin positions and coincident pin contacts, and preservation of explicit bends and electrical connections across move, rotation, save/open and undo. Native checks wired the reference symbols by mouse at 25%, added a junction at 400%, and verified marker changes and continued connectivity when rotating and dragging the inverter.

The CD4029 addition passed all 100 macOS Xcode tests on 20 November 2026. Coverage includes up/down rollover in both modes, asynchronous JAM, carry inhibit and cascading, floating controls, supply loss and recovery, KiCad import, and archive round-trip.

The macOS Xcode build and full test suite passed on 20 November 2026 after adding CD4071. The first integration run exposed missing support for its multi-arc KiCad outline; the symbol loader was extended and the rerun passed. The OR-gate symbol was also checked in the running Workbench. A subsequent full test run passed after restoring File menu commands and adaptive file controls. Saving, clearing, and reopening a circuit were verified through the native dialogs.

The capacitor/RC timing addition passed the full suite: 84 test case executions, zero failures. Native UI checks confirmed both KiCad symbols, µF/nF editors, rejection of zero, and saving/clearing/reopening 47 µF and 22 nF capacitors. One initial timing test incorrectly expected five downstream edges after advancing through six; its time interval was corrected. A later mixed-clock test exposed its reliance on wall time after advancing virtual time; the Workbench now accepts an optional test time source, and this regression uses a consistent deterministic clock. All tests passed. Xcode reported only skipped App Intents metadata extraction (no AppIntents dependency).

Coverage includes:

- Capacitor value validation, physical symbols, DC isolation, Undo/Redo, archive validation and round-trip, exponential charge curve, astable startup and steady-state durations, monostable timeout/reset/held trigger, R/C scaling, downstream counting, bounded time batches, power cycling, reversed polarity, unsupported wiring, and automatic Workbench oscillator restart on reopen.

- NE555 four-state controls, reset/trigger priority, latch retention, discharge and weak pull-up, power-loss invalidation/restoration, incorrect rail provenance, downstream X, Automatic Power, KiCad symbol pins, and archive round-trip.

- Logic states, net resolution, gates, and clock-edge detection.
- CD4071 physical pin mapping, all four gates with LOW/HIGH/X/HIGH-Z inputs, shared package allocation, KiCad symbols, Explicit and Automatic Power, downstream propagation, supply-loss Undo, and save/reopen.
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
- RC simulation is limited to the standard NE555 astable and monostable networks described above. Standalone or arbitrary RC networks, multiple timing capacitors, extra timing-node loads, routing through analog switches, leakage, ESR, tolerances, saturation voltage and general analog node voltages are not modelled. Unsupported timing wiring produces an orange warning and X (except asserted RESET still forces LOW).
- Leave CONT open or bypass it to GND with a capacitor. Externally driven control voltages remain unsupported and produce X unless RESET is asserted. C_Small may be reversed; reversed C_Polarized timing capacitors are rejected. Timing resistor supply and capacitor reference connections require actual +5 V/GND rail sources, even in Automatic Power mode.
- Recognised timing capacitors start at 0 V after circuit rewiring/reopening or power restoration; retained real-world charge is not modelled. Value edits preserve the current ideal voltage. RC timing-node voltages are used internally by the timer, not exported as general analog pin readings. Capacitors otherwise remain open circuits in digital simulation.
- CD4060 supports an external digital clock. Its RC/crystal oscillator circuitry is not simulated.
- CD40106 uses digital inversion and does not model analog Schmitt thresholds or hysteresis.
- The discrete DC operating-point model covers mixed diode and grounded-emitter transistor networks. General analog analysis, propagation delays, leakage, and back-powering remain future work.
- Automatic supply voltage is currently fixed at 5 V.
- High requested clock rates can exceed real-time processing capacity in larger circuits.
- Build and verify the complete 12/24-hour clock incrementally against the reference KiCad schematic.
- Plan rotary encoder emulation for a future clock time-setting workflow.
- Expand the KiCad symbol allowlist and use the shared import topology for future schematic-image inputs.
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

**Last confirmed milestone:** On 23 November 2026 the macOS Debug build succeeded and all 150 automated tests passed across 37 suites. Coverage includes package and schematic pin geometry, CD4070 XOR units, CD4510/CD4511 physical pin mapping, wired display behaviour, wire defaults and recolouring, rotation and connected moves, scope probe and cursor behaviour, and circuit archive round-trips.

The rebuilt native app opened successfully. The View menu switched from Schematic to Physical DIP and the drawing palette changed from Green to Black. In the frozen oscilloscope, dragging both cursor handles updated both timestamps, Δt and the reciprocal. This pass did not visually compare the five component symbols and physical faces or exercise right-click recolouring, probe placement, native Save/Open, or dragging and rotating wired parts by mouse. Those paths were reviewed in code and their underlying behaviour was covered where available by the automated suite.

**Suggested next task:** Continue sequential power-loss handling with CD4510, keeping its unknown-input and clock-transition work in a clearly scoped stage.

Read this status file and inspect the current working tree when resuming development. Update the document after significant features, architectural decisions, or confirmed issues.
