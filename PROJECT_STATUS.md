# CMOS Hardware Simulator — Project Status

**Project:** CMOS Hardware Simulator  
**Platform:** macOS / SwiftUI / Xcode  
**Repository:** https://github.com/writetomarkadams/CMOS_Hardware_Simulator  
**Branch:** main  
**Last updated:** 28 November 2026\
**Project root:** /Users/mark.adams/Documents/GitHub/CMOS_Hardware_Simulator

Use this project root for all development. Leave the previous project location untouched.

## 1. Project Overview

A macOS application for building and simulating electronic circuits, with an initial focus on CMOS 4000-series integrated circuits.

The application opens directly into the Circuit Workbench. Users can place components, wire individual physical pins, configure sources and indicators, and run digital simulations. The longer-term target is a complete CMOS 12/24-hour clock.

The macOS app includes an AppIcon asset in Debug and Release. The built app keeps the bundle name CMOS4000Simulator.

### Workbench changes verified on 27 November 2026

- The native arm64 macOS build and full Xcode suite passed. Xcode reported 209 tests, zero failures and zero skips. Coverage included the 74HC08, mechanical switches, the series 2N3904 pull-down and all three SN74LS counters.
- The component library groups parts by family and exposes the oscilloscope under Instruments. The 74HC group also includes 74HC00, 74HC02, 74HC04, 74HC14, 74HC32 and 74HC86 with full-package and individual-unit placement. The shared geometry regression covers their schematic pins. Dedicated truth-table and import tests in this change cover 74HC08. The 74HC14 is a digital approximation with no hysteresis state.
- Physical TO-92 rendering uses an outlined housing with black markings.

### 74HC08 quad AND gate

- The device models the Texas Instruments commercial SN74HC08N in the N
  (PDIP-14) package. Sections 4 and 7.4 give the top-view pinout and function
  table. The library offers a complete 74HC08 Package and separately placeable
  AND units with shared power unit E. The package reuses the CD4070 DIP artwork.
  [TI SN74HC08 datasheet, SCLS081J, February 2025](https://www.ti.com/lit/ds/symlink/sn74hc08.pdf)
- KiCad imports map `74xx:74HC08` and `74xx_IEEE:74HC08` by physical pin number.
  The installed KiCad library's pin-compatible `74xx:74LS08` symbol also maps
  when its value explicitly reads `74HC08`. Units A–E share the same model.
- TI §5.3 recommends 2–6 V across VCC and GND. This is a device rating.
  Explicit Power uses ChipSim's +5 V and ground rails. Missing or incorrect
  rails make every output X. Automatic Power assumes ideal 5 V operation.
  With binary inputs, the outputs follow the AND function table exactly.
  A known LOW determines the result with a floating or unknown partner.
  Other unresolved combinations yield X.
- At VCC = 2, 4.5 and 6 V, TI §5.3 lists maximum VIL of 0.5, 1.35 and 1.8 V
  and minimum VIH of 1.5, 3.15 and 4.2 V across the recommended operating
  temperature range. When the existing discrete DC solver supplies a voltage,
  ChipSim uses inclusive VIL ≤ 1.5 V and VIH ≥ 3.5 V, interpolated between the
  4.5 and 6 V rows for its fixed 5 V rails. Intermediate voltages are X.
  Nets without a DC solution use their resolved digital levels.
- The regression fixture checks all four gates against the function table
  with ideal 0 V/5 V inputs and unloaded outputs. The DC fixture holds one
  input at +5 V and checks a resistor divider at 1.4, 1.6, 3.4 and 3.6 V
  (voltage tolerance 1 µV) for LOW, X, X and HIGH. Its reverse-biased LED
  enables the existing solver without loading the divider in that model.
  The regression also checks CD4081's existing DC conversion on the same net.
- Outputs are ideal digital drivers. Propagation delay, slew, output droop
  and drive limits, current draw, leakage, input capacitance, clamp currents,
  floating-input transients, and temperature dependence are outside this
  model. The simulator has no variable supply or general analog solver to
  verify operation across the full recommended supply range.

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

- Physical DIP appearance also draws axial resistors, 1N4148 diodes and capacitors. Resistor bands and capacitor markings follow edited values. Values without an exact band or small-capacitor body code retain their numeric labels. The diode stripe marks pin 1 (cathode), and the polarized capacitor stripe marks pin 2 (negative). The printed 16 V capacitor marking is artwork only.
- Transistor designations share a top-down TO-92 package view with numbered contacts and designation-specific terminal labels. Connections follow the existing physical pin numbers when switching views or rotating. Designation changes that would alter the terminal layout or schematic symbol are disabled for wired parts and parts with imported graphics. The library transistor schematic artwork depends on the locally installed KiCad symbols.

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
| 2N3904 | Digital NPN low-side switch and limited grounded-emitter DC approximation |
| BC547B | onsemi BC547BG, digital NPN low-side switch and separate limited DC approximation |
| 2N3906 | onsemi PNP, ideal active-LOW digital high-side switch |
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
- A preset can load any four-bit pattern. An enabled decade count from a possible value above nine makes all Q bits X. Workbench Save/Open retains the device and wiring. KiCad import accepts `4xxx:4029` and `4xxx_IEEE:4029` using physical pin numbers. [TI CD4029B datasheet](https://www.ti.com/lit/ds/symlink/cd4029b.pdf)

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

The engine invokes the `powerDidFail()` hook when it first observes an unpowered chip. Sequential models use the hook to discard stored state and reset edge detectors where applicable.

Implemented for:

- CD4027
- CD4029
- CD4060
- CD4510
- CD4017
- CD4026
- CD4516
- CD4518
- CD4520
- CD4511 and CD4543
- NE555
- SN74LS90, SN74LS92 and SN74LS93

A powered input operation can establish state after restoration. Counters
and flip-flops use their supported reset, set, preset or clocked operations.
CD4027 toggle mode cannot resolve an unknown prior state. CD4511 and CD4543
recover by sampling BCD in transparent mode. In hold mode, powered output
overrides can drive the segments while the stored code remains unknown.

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

The onsemi 2N3904 uses TO-92 case 135AN, with pins 1 emitter, 2 base and 3 collector from left to right facing the flat side with leads down. The simulator uses two paths.

- **Digital** — A LOW base releases the collector. A HIGH base and LOW emitter drive it LOW. Other states drive X. A simple resistive pull-up and base-resistor stage uses this path, so its logic state does not imply a measured saturation voltage or base current.
- **Series digital** — Two onsemi 2N3904s with a direct, two-pin upper-emitter to lower-collector junction and the lower emitter held at GND can act as a series pull-down in the ideal 5 V digital model. A known LOW at the lower base opens the path, allowing the upper collector to release a resistive pull-up even when the upper base is HIGH and the junction floats. When both bases are HIGH, the existing digital model pulls LOW. Base levels come from settled nets, including rails selected by mechanical SPDTs. The regression fixture uses +5 V, an 820 Ω pull-up and two 10 kΩ base resistors. It checks all four logic combinations and an open switch throw. This path applies ideal cutoff and conduction, using no fitted electrical parameters or SPICE model. It does not calculate midpoint voltage, require a particular resistor value, or verify base drive, loading, saturation headroom or switching time. Junctions with extra connections and open or ambiguous base inputs retain the ordinary digital rules.
- **DC** — A connected region qualifies with a physical LED (LED3mm) or a combination of a 1N4148 and a supported NPN transistor. The discrete pass requires at most 32 nodes, compatible ideal 0 V/5 V drivers, emitters fixed at 0 V and a resistive path from every unknown node to an ideal driver. An ineligible region or failed solve retains digital evaluation. A CD4051 or another modeled CMOS analog switch bypasses the discrete DC pass. Mechanical contacts join digital nets, while regions touching mechanical switch terminals are excluded from the DC pass. A scope probe can show solved DC voltage. The solver classifies voltages at or below 0.8 V as LOW, at or above 2.0 V as HIGH, and those between as X.
- **DC approximation** — The base current uses a 0.68 V knee and a 50 Ω slope resistance, clipped at zero. The collector law blends 100 times the base current (dimensionless multiplier) with the positive collector-emitter voltage divided by 20 Ω. All four values are solver inputs with undocumented derivation. The static model bounds trial voltages to 0–5 V and omits leakage, reverse conduction, breakdown, capacitance, charge storage, switching time, temperature, self-heating and device-rating enforcement.

The [onsemi 2N3904/D datasheet, October 2024, Rev. 3, pp. 1–2](https://www.onsemi.com/pdf/datasheet/2n3904-d.pdf) specifies the following on-characteristics at 25 °C for pulses up to 300 µs at up to 2% duty cycle. The simulator uses static resistive fixtures at the same terminal operating points. Tests characterize the current implementation and keep the datasheet comparison separate.

| Condition | onsemi limit | ChipSim DC approximation |
| --- | --- | --- |
| 10 mA collector, 1 V collector-emitter | DC gain 100–300 | 80, below minimum |
| 10 mA collector, 1 mA base | VCE(sat) ≤ 0.20 V, VBE(sat) 0.65–0.85 V | 0.222 V and 0.730 V, with VCE above maximum |
| 50 mA collector, 5 mA base | VCE(sat) ≤ 0.30 V, VBE(sat) ≤ 0.95 V | 1.111 V and 0.930 V, with VCE above maximum |

The existing 5 V diode AND and two-transistor circuit is a separate integration fixture with 10 kΩ resistors. It lights the logic LED only when both inputs are HIGH.

### BC547B transistor designation

The Workbench's Transistor Properties offers **BC547B**, based on the onsemi **BC547BG** B-grade part with straight leads, TO-92 case 29, style 17. Pins are **1 collector, 2 base, 3 emitter**. Looking down onto the package with its flat edge nearest you, the physical view reads C–B–E from left to right. Facing the flat side with the leads down gives the same lead order. KiCad's `Transistor_BJT:BC547` C–B–E symbol imports as the B grade, as does an explicit `Transistor_BJT:BC547B` symbol. The symbol and package rotate with their existing numbered endpoints. Designation changes that would swap collector and emitter are blocked on wired parts and parts with imported symbol graphics. Existing 2N3904 archives retain their E–B–C pinout and default designation. [onsemi BC546/D, August 2021, Rev. 8, pp. 1–2 and ordering/package drawings](https://www.onsemi.com/pub/Collateral/BC546-D.PDF)

BC547B reuses the ideal digital switch and the DC eligibility and fallback above. Its limited DC approximation uses separate solver inputs. The dimensionless multiplier of 290 follows the typical B-grade gain at 2 mA and VCE = 5 V. The clipped base law uses an empirical 0.675 V knee and a 50 Ω slope chosen together to give about 0.675 V at that gain point and 0.700 V at 0.5 mA base drive. The 5 Ω collector slope is a fitting value that keeps both forced-gain-20 points below their voltage maxima. The model makes saturation voltage proportional to collector current at a fixed forced gain, so it cannot reproduce both typical saturation voltages with one slope.

| Condition at 25 °C | onsemi data | ChipSim DC approximation |
| --- | --- | --- |
| 2 mA collector, VCE = 5 V | Gain 200–450, typical 290. VBE(on) 0.55–0.70 V | Gain 289.4 and VBE 0.675 V. The circuit test uses 4.99 V with a 10 mV sense drop. |
| 10 mA collector, 0.5 mA base | VCE(sat) typical 0.09 V, maximum 0.25 V. VBE(sat) typical 0.70 V. | VCE 0.054 V and VBE 0.700 V |
| 100 mA collector, 5 mA base | VCE(sat) typical 0.20 V, maximum 0.60 V | VCE 0.537 V. This is a boundary check at the device's continuous current rating. |

These checks cover static grounded-emitter switching in eligible 0–5 V regions. The collector law overestimates typical gain at the 10 µA and 100 mA active-region datasheet points (about 290 vs 150 and 261 vs 180, respectively, at 5 V). Gain variation with current, reverse bias, leakage, breakdown, switching transients, thermal behavior and rating enforcement are outside the approximation. Use the model for basic switching experiments. Its numerical checks cover the listed bias points.

### 2N3906 transistor designation

The model represents the onsemi **2N3906**, unsuffixed straight-lead bulk part in **TO-92 case 29, style 1**. Pins are **1 emitter, 2 base, 3 collector** from left to right facing the flat side with the leads down. In ChipSim’s top-down TO-92 view the flat edge is nearest the viewer and the leads read E–B–C. The KiCad `Transistor_BJT:2N3906` symbol uses the same numbered roles and its emitter arrow points toward the base. See the pin and package drawings and ordering table. [onsemi 2N3906/D, February 2010, Rev. 4, pp. 1–3 and case drawing](https://www.onsemi.com/pdf/datasheet/2n3906-d.pdf)

Define VXY = VX − VY and take current entering a pin as positive. In forward conduction a PNP emitter is above its base, so VEB is positive and conventional current enters E and leaves B and C. In forward active operation the collector is below the base. In saturation both emitter–base and collector–base junctions are forward biased and the collector approaches the emitter voltage. ChipSim implements only the digital endpoints for an ideal HIGH emitter in its 0/5 V logic environment.

| Emitter | Base | Collector drive |
| --- | --- | --- |
| HIGH | HIGH | High impedance, representing cutoff |
| HIGH | LOW | Ideal HIGH, representing an asserted high-side switch |
| Any other input combination | | X |

With a pull-down from collector to ground, the digital switching fixture expects exactly HIGH → LOW → HIGH as the base changes LOW → HIGH → LOW. Additional fixtures check disconnected inputs and confirm that a physical LED on the collector does not produce an analog solution on that node. Use a Logic LED or logic probe to observe switching.

The existing DC solver requires an emitter fixed at 0 V and stamps NPN current from base and collector into the emitter. PNP active-region gain, base current and saturation voltage require a separate solver model and review. A region that touches the digital PNP collector stays on the digital path, so an asserted collector does not masquerade as a DC source for a physical LED. There are no fitted PNP analog inputs, leakage, breakdown, rating checks, capacitance, thermal effects or switching delays.

The following datasheet values are reference data only. On-characteristics use 25 °C ambient and pulses of at most 300 µs and 2% duty cycle. Voltage and current limits are expressed as magnitudes for the PNP device.

| Parameter | onsemi datasheet value |
| --- | --- |
| Absolute maximum voltage magnitudes | 40 V collector–emitter, 40 V collector–base, 5 V reverse emitter–base |
| Absolute maximum continuous collector current magnitude | 200 mA |
| DC gain at 10 mA collector current and 1 V collector–emitter magnitude | 100–300, dimensionless |
| Saturation at 10 mA collector and 1 mA base current magnitudes | Collector–emitter maximum 0.25 V, emitter–base 0.65–0.85 V |
| Saturation at 50 mA collector and 5 mA base current magnitudes | Collector–emitter maximum 0.40 V, emitter–base maximum 0.95 V |

## 6. Verification and Current Milestone

On 25 November 2026, the macOS build and full Xcode suite passed 189 tests across 216 executions, with zero failures or skips. The suite covered clock sources and edge handling, navigation, axial markings and pin geometry, TO-92 pin mapping and rotation, archive compatibility, 2N3904 and BC547B switching and DC fixtures, 2N3906 digital switching and DC isolation, and all four input combinations of the diode–transistor AND fixture. The app icon was verified in the built bundle. The suite did not include a manual visual or pointer-interaction pass.

On 21 November 2026 the macOS build and full Xcode suite passed with the grid-aligned pin geometry. Added coverage checks the library’s pin identity and grid positions through all four rotations, the CD4510 and CD40106 pin mapping, zoomed hit targets from 25–400%, crossing and marker visibility, imported mirrored pin positions and coincident pin contacts, and preservation of explicit bends and electrical connections across move, rotation, save/open and undo. Native checks wired the reference symbols by mouse at 25%, added a junction at 400%, and verified marker changes and continued connectivity when rotating and dragging the inverter.

The CD4029 addition passed all 100 macOS Xcode tests on 20 November 2026. Coverage includes up/down rollover in both modes, asynchronous JAM, carry inhibit and cascading, floating controls, supply loss and recovery, KiCad import, and archive round-trip.

The macOS Xcode build and full test suite passed on 20 November 2026 after adding CD4071. The first integration run exposed missing support for its multi-arc KiCad outline; the symbol loader was extended and the rerun passed. The OR-gate symbol was also checked in the running Workbench. A subsequent full test run passed after restoring File menu commands and adaptive file controls. Saving, clearing, and reopening a circuit were verified through the native dialogs.

The capacitor/RC timing addition passed the full suite: 84 test case executions, zero failures. Native UI checks confirmed both KiCad symbols, µF/nF editors, rejection of zero, and saving/clearing/reopening 47 µF and 22 nF capacitors. One initial timing test incorrectly expected five downstream edges after advancing through six; its time interval was corrected. A later mixed-clock test exposed its reliance on wall time after advancing virtual time; the Workbench now accepts an optional test time source, and this regression uses a consistent deterministic clock. All tests passed. Xcode reported only skipped App Intents metadata extraction (no AppIntents dependency).

Coverage includes:

- Capacitor value validation, physical symbols, DC isolation, Undo/Redo, archive validation and round-trip, exponential charge curve, astable startup and steady-state durations, monostable timeout/reset/held trigger, R/C scaling, downstream counting, bounded time batches, power cycling, reversed polarity, unsupported wiring, and automatic Workbench oscillator restart on reopen.

- NE555 four-state controls, reset/trigger priority, latch retention, discharge and weak pull-up, power-loss invalidation/restoration, incorrect rail provenance, downstream X, Automatic Power, KiCad symbol pins, and archive round-trip.

- Logic states, net resolution, gates, and clock-edge detection.
- CD4071 physical pin mapping, all four gates with LOW/HIGH/X/HIGH-Z inputs, shared package allocation, KiCad symbols, Explicit and Automatic Power, downstream propagation, supply-loss Undo, and save/reopen.
- CD4510 controls, power-loss invalidation, reset and BCD preset recovery, high-clock restoration, carry behaviour, and synchronous cascading in both power modes.
- CD4027 state loss, restoration with CLK already HIGH, downstream X propagation, and Automatic Power.
- Shared package allocation, power units, supply validation, Undo, and older-file migration.
- CD4511/CD4543 supply-loss invalidation, transparent recovery, hold, output overrides, invalid BCD blanking, wired seven-segment displays and downstream X.
- MAN72A polarity, symbol pin mapping, CD4543 integration, and save/reopen.
- New counter rollover, inhibit/enable behaviour, preset, RESET, carry cascading, power loss, symbols, and archive integration.
- CD4051/CD4052/CD4053 selector combinations, inhibit, floating controls, two-way propagation, switch cascades, contention, weak pulls, power loss and restoration, symbol pin mapping, and Workbench save/reopen.

Live Workbench checks have verified wiring previews and bends, wire deletion, Undo/Redo shortcuts, placement after scrolling, junctions, file reopening, separate power symbols, and the CD4026 library entry and rendered symbol.

Previous project notes record successful builds and launches on both the work and home Macs. The latest features have been tested on the current development Mac; their latest home-Mac build has not been independently confirmed.

Check commit and push status before switching Macs.

## 7. Known Limitations and Next Development Tasks

- Phases 4B.1–4B.3 cover unknown and floating controls on CD4510,
  CD4516, CD4029 and CD4060. Phase 4C.1 covers CD4017 and CD4026.
  Phase 4C.2 covers CD4518 and CD4520. Phase 4D covers CD4027 JK
  flip-flop control uncertainty. Phase 4E covers CD4511 and CD4543
  display latch and output-control uncertainty. Phase 4F covers SN74LS90,
  SN74LS92 and SN74LS93 asynchronous reset and preset uncertainty.
- Phase 5 reviews uncertain clock transitions and simultaneous edge ordering.
  Existing edge detection recognises definite LOW→HIGH and HIGH→LOW transitions.
- Phase 6 reviews simulation convergence and feedback loops.
- RC simulation is limited to the standard NE555 astable and monostable networks described above. Standalone or arbitrary RC networks, multiple timing capacitors, extra timing-node loads, routing through analog switches, leakage, ESR, tolerances, saturation voltage and general analog node voltages are not modelled. Unsupported timing wiring produces an orange warning and X (except asserted RESET still forces LOW).
- Leave CONT open or bypass it to GND with a capacitor. Externally driven control voltages remain unsupported and produce X unless RESET is asserted. C_Small may be reversed; reversed C_Polarized timing capacitors are rejected. Timing resistor supply and capacitor reference connections require actual +5 V/GND rail sources, even in Automatic Power mode.
- Recognised timing capacitors start at 0 V after circuit rewiring/reopening or power restoration; retained real-world charge is not modelled. Value edits preserve the current ideal voltage. RC timing-node voltages are used internally by the timer, not exported as general analog pin readings. Capacitors otherwise remain open circuits in digital simulation.
- CD4060 supports an external digital clock. Its RC/crystal oscillator circuitry is not simulated.
- CD40106 uses digital inversion and does not model analog Schmitt thresholds or hysteresis.
- The discrete DC operating-point model covers mixed diode and grounded-emitter transistor networks. General analog analysis, propagation delays, leakage, and back-powering remain future work.
- Automatic supply voltage is currently fixed at 5 V.
- High requested clock rates can exceed real-time processing capacity in larger circuits.
- Phase 7 builds and verifies the complete 12/24-hour clock incrementally against the reference KiCad schematic.
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

**Recorded baseline:** On 27 November 2026, the native arm64 macOS Debug build succeeded and all 209 tests passed across 41 suites at commit `0508b2b`. Coverage includes 74HC08 logic, SN74LS90/92/93 counters, mechanical switches, series transistor behaviour, and existing clock regressions.

### CD4510 Phase 1 verification on 27 November 2026

- The clean WORK Mac checkout at `af137a7` reproduced the `0508b2b` baseline
  with 209 passing tests across 41 suites and 273 executions including parameterized
  cases. The intervening commit changes only this status document.
- With the local Phase 1 changes, the native arm64 macOS Debug build succeeded
  in Xcode 27.2. The full suite passed 211 tests across 41 suites, with 278
  executions, zero failures, and zero skips. All 209 baseline test identities
  remained passing. The build emitted the existing App Intents metadata warning.
- The model follows the TI CD4510BE top-view PDIP-16 pinout, CD4510B timing
  diagram and truth table (Fig. 15, p. 3-253), and common-clock cascade
  description. Reset and preset are asynchronous and active HIGH. Counting
  uses a rising clock with active-LOW carry-in, and terminal carry is active
  LOW. [TI CD4510B datasheet, SCHS071B, July 2003](https://www.ti.com/lit/ds/symlink/cd4510b.pdf)
- In Explicit Power, invalid ideal +5 V or GND rails invalidate the count
  and clock history through the shared power hook. The engine drives the
  unpowered outputs X. On restoration, the first clock sample establishes
  the level. Q remains X until reset or a valid BCD preset. A HIGH carry-in
  still forces powered carry-out HIGH. Automatic Power assumes valid
  rails and can restore a chip previously invalidated in Explicit Power.
- Tests compare exact settled logic levels and counts with ideal rails and
  discrete clock transitions. They exercise missing and incorrect VDD,
  reset and preset recovery with clock already HIGH, and common-clock
  cascading through 00–99 in both directions and both registration
  orders in each power mode.
- Power-loss invalidation is a digital simulator convention. The model
  retains its initial zero for a fresh, powered instance and accepts BCD
  presets 0–9. Supply ramps, retention voltage, non-BCD preset sequences,
  propagation delays and physical ripple glitches are outside this check.
  Unknown controls and uncertain clock transitions remain separate work.
  The full six-digit reference clock was outside this verification.

During the 23 November native UI check, the rebuilt app opened successfully. The View menu switched from Schematic to Physical DIP and the drawing palette changed from Green to Black. In the frozen oscilloscope, dragging both cursor handles updated both timestamps, Δt and the reciprocal. This pass did not visually compare the five component symbols and physical faces or exercise right-click recolouring, probe placement, native Save/Open, or dragging and rotating wired parts by mouse. Those paths were reviewed in code and their underlying behaviour was covered where available by the automated suite.

### CD4060 Phase 2 verification on 27 November 2026

- The CD4060 model follows the TI CD4060BE top-view PDIP-16 pinout and
  description. Pin 11 accepts the external clock, active-HIGH RESET on
  pin 12 asynchronously clears all 14 stages, and the counter advances on
  falling clock edges. Pin 3 is Q14 (÷16,384).
  [TI CD4060B datasheet, SCHS049C, October 2003](https://www.ti.com/lit/ds/symlink/cd4060b.pdf)
- In Explicit Power, invalid +5 V (VDD, pin 16) or ground (VSS, pin 8)
  clears the stored count and clock history through the shared power hook.
  The engine drives the unpowered outputs X. After restoration the first
  clock sample establishes the level and the divider outputs stay X until
  a powered RESET HIGH. A fresh instance still starts with an unknown count.
  Automatic Power assumes valid ideal rails.
- Tests compare exact settled digital levels for missing VDD, logic LOW
  without GND rail identity, restoration at either clock level, and
  asynchronous reset recovery. They verify all ten exposed ratios through
  14-bit rollover in both power modes. The wired Explicit Power reference
  uses the Workbench clock scheduler with deterministic simulated time.
  At 32,768 Hz, CD4060 pin 3 supplies 2 Hz to the toggling CD4027. CD4027
  rising edges at 0.25 s and 2.25 s span two 1 Hz periods, with the
  intervening rise at 1.25 s. Timing is checked at exact half-cycle
  boundaries with ideal rails and unloaded outputs.
- Power-loss invalidation is a digital simulation convention. The model
  covers an ideal external clock, with oscillator analog behavior, supply
  ramps, physical ripple delays, uncertain-clock changes, wall-clock
  throughput, and the full reference clock outside this verification.
- The native arm64 macOS Debug build and full suite passed in Xcode 27.2.
  The Phase 1 baseline reproduced 211 tests across 41 suites (278
  executions). Phase 2 passed 214 tests across 42 suites (285 executions),
  with zero failures or skips and all 211 baseline identities preserved.
  Xcode emitted the existing App Intents metadata warning.

### CD4511/CD4543 Phase 3 verification on 27 November 2026

- The TI CD4511BE top-view PDIP-16 pinout and truth table (p. 3-258)
  specify LE (5) LOW for transparent operation and HIGH for hold. LT (3)
  LOW drives all segments HIGH and takes priority over BI (4) LOW,
  which drives them LOW. [TI CD4511B, SCHS072B, July 2003](https://www.ti.com/lit/ds/symlink/cd4511b.pdf)
- The TI CD4543BE top-view PDIP-16 pinout and truth table (p. 3-333)
  specify LD (1) HIGH for transparent operation and LOW for hold. BI (7)
  HIGH blanks the display. PH (6) HIGH inverts all output levels,
  including the blanked levels. Use PH LOW for common cathode and HIGH for
  common anode. [TI CD4543B, SCHS086D, April 2004](https://www.ti.com/lit/ds/symlink/cd4543b.pdf)
- Invalid VDD (16) or VSS (8) in Explicit Power clears the stored code
  through the shared power hook and drives all seven outputs X. A fresh
  latch starts unknown. Restoring power in hold leaves the stored code
  unknown. Powered blanking and CD4511 lamp test still drive definite
  levels. Releasing either override in hold exposes the unknown state.
  Powered transparent operation samples the inputs, which hold retains.
  Definite BCD codes 10–15 still decode to blank and can be retained.
- The engine fixtures compare exact settled logic levels with ideal +5 V
  and GND. They cover both power modes, missing VDD, VSS without ground
  identity, recovery in hold and transparent modes, control priority,
  both CD4543 phases, MAN74A and MAN72A segment inputs and illumination,
  and propagation of X through a separately powered CD40106 inverter.
- The WORK Mac native arm64 macOS Debug build and full Xcode 27.2 suite
  passed on a copy of the local working tree. The pre-change run reproduced
  all 214 Phase 2 identities across 42 suites (285 executions). Phase 3
  passed 217 tests across 43 suites (294 executions), with zero failures
  or skips and all 214 baseline identities passing. Xcode emitted the
  existing App Intents metadata warning.
- This digital model omits supply ramps, retention voltage, propagation
  delays, setup and hold timing, display current and LCD backplane effects.
  Uncertain-control semantics are Phase 4 work. This phase used automated
  wired fixtures and left manual UI and full reference-clock checks for
  later verification.

### CD4510/CD4516 Phase 4B.1 verification on 27 November 2026

- The TI CD4510BE and CD4516BE top-view PDIP-16 pinout, truth table and
  figures 15–16 specify asynchronous active-HIGH RESET before active-HIGH
  PE, then counting on a rising CLOCK with active-LOW CI. Direction HIGH
  counts up. The model uses active-LOW CO at the direction's terminal count
  with CI LOW and samples the settled carry from before the edge in a
  common-clock cascade. [TI SCHS071B, July 2003](https://www.ti.com/lit/ds/symlink/cd4516b.pdf)
- Each counter stores whole-count candidates (up to 10 for CD4510 and 16
  for CD4516). Each resolved X or Z control or preset bit admits both
  levels. Q bits report consensus independently. Carry uses the resulting
  count and the CI and direction values from the same branch. Identical
  control samples retain that carry through repeated settling without
  counting again. Definite non-BCD CD4510 presets still hold the previous
  count. For a partial preset, each invalid completion also contributes
  the held count.
- Fresh CD4510 starts at zero and fresh CD4516 starts unknown. Invalid
  Explicit Power clears the stored certainty and clock history. Automatic
  Power assumes ideal rails. Restoring power with CLOCK already HIGH
  establishes the clock level. RESET and valid presets recover known counts.
- Tests compare exact digital levels with ideal +5 V and GND or Automatic
  Power, including both X and Z, the Phase 4A audit cases, ambiguous
  controls and partial presets, recovery of known bits, weak pull
  resolution, power loss and restoration, and repeated settling.
  Common-clock tests cover both count directions and component registration
  orders in both power modes. Two existing CD4510 fixtures now explicitly
  establish inactive controls or reset after wiring.
- The WORK Mac native arm64 macOS Debug build and full Xcode 27.2 suite
  passed on a copy of the local working tree. Phase 4A reproduced 217 tests
  in 43 suites (294 executions). Phase 4B.1 passed 222 tests in 44 suites
  (312 executions), with zero failures or skips. All 217 baseline test
  identities passed, including the existing clock regressions. Xcode
  emitted the existing App Intents metadata warning.
- The ideal digital model treats distinct receiver inputs independently,
  even when they share an uncertain net. Across effective control changes
  or another edge, the candidate set retains whole counts and drops the
  prior association between counts and sampled control values. Downstream
  components see only the settled pin consensus. These limits can produce
  additional X readings in correlated circuits. Propagation delays and
  analogue timing are outside the model. Uncertain clock transitions
  retain the existing edge qualification and are deferred to Phase 5.

### CD4029 Phase 4B.2 verification on 27 November 2026

- The TI CD4029BE top-view PDIP-16 pin diagram and description (page 1)
  specify asynchronous active-HIGH PRESET ENABLE, LOW CARRY IN to enable
  counting, LOW-to-HIGH CLOCK, HIGH binary select, HIGH up select, and
  active-LOW terminal carry. Figure 17 shows parallel clocking.
  [TI CD4029B datasheet, SCHS034C, October 2003](https://www.ti.com/lit/ds/symlink/cd4029b.pdf)
- The ideal digital model retains up to 16 whole-count candidates. X and Z
  at each resolved control or JAM receiver admit LOW and HIGH. Q bits
  drive their consensus. A possible preset loads every matching JAM value
  asynchronously. A possible normal branch holds or counts based on CI
  and the definite clock edge. Each branch calculates CO from its own
  count, mode, direction and CI. CI HIGH forces CO HIGH. Common-clock
  stages sample resolved pre-edge carry and consume the edge once.
- JAM accepts 0 through 15 in either mode. A held or newly preset non-BCD
  count keeps its Q bits, with uncertain CO in an enabled decade branch.
  If any enabled decade transition starts above nine, that branch contributes
  all 16 four-bit values and both carry levels. This covers mixed sets with
  valid and invalid decade transitions conservatively. Other branches
  still contribute their own outcomes.
- Fresh instances and invalid Explicit Power have no known count.
  Power loss clears clock history, so restoration with CLOCK already
  HIGH does not count. A definite preset can establish a new count.
  Automatic Power assumes ideal rails.
- Regressions exercise exact digital levels with ideal +5 V/GND or Automatic
  Power. Coverage includes X and Z controls and JAM, recovery, terminal
  carry, weak pulls and contention, invalid decade transitions, supply
  faults, and repeated settling. Common-clock cascades cover both modes,
  directions, registration orders and power modes. The existing
  preset-and-inhibit test adds an assertion for HIGH carry after the
  uncertain-CI rollover. The new ambiguous-PE edge fixture settles CLOCK
  LOW before changing PE and raising CLOCK together, isolating the concurrent
  preset and count branches from an earlier asynchronous preset.
- On the WORK Mac with Xcode 27.2, the native arm64 Debug build and full
  suite passed on a copy of the local working tree. Phase 4B.1 reproduced
  222 tests in 44 suites (312 executions). Phase 4B.2 passed 229 tests in
  45 suites (334 executions), with zero failures or skips. All 222 baseline
  test identities and their parameterised cases passed, including the
  clock regressions. The existing App Intents metadata warning remains.
  The clean baseline build also emitted Swift actor-isolation warnings
  from the earlier CD4510/CD4516 test suite.
- The model treats separate uncertain inputs independently and retains
  control/count association for carry only until an effective input change
  or another edge. Downstream stages receive settled pin consensus.
  Uncertain clock transitions remain Phase 5 work. Propagation delays,
  analogue timing and hardware behaviour outside the modeled counting
  sequences are outside this digital abstraction.

### CD4060 Phase 4B.3 verification on 27 November 2026

- TI's CD4060BE PDIP-16 top-view pinout and functional description specify
  14 counter stages, falling-edge counting on external clock pin 11,
  an asynchronous active-HIGH reset on pin 12, and Q14 on pin 3.
  Phase 4A identified that X or Z RESET discarded even a definite zero.
  The model now retains zero plus either the held counts or their successors
  on a definite falling edge. Definite HIGH clears to zero. Each divider
  output drives the consensus of whole-count candidates, preserving sparse
  correlations during later transitions. Resolved weak pulls can establish a
  definite RESET and conflicting strong drivers yield X.
  [TI CD4060B datasheet, SCHS049C, October 2003](https://www.ti.com/lit/ds/symlink/cd4060b.pdf)
- A singleton is a scalar with a masked increment. Partially uncertain
  states use sorted, merged inclusive ranges. Advancing shifts those ranges
  modulo 16,384, and optionally inserts zero. Consensus comes from range
  endpoints and the bit positions that vary within each range. Work scales
  with the number of ranges. A fully unknown sentinel needs no heap storage
  and stays invariant on hold, increment, or possible reset. Definite reset
  recovers zero after startup or power loss. The power hook clears clock
  history, so the first restored sample establishes a level. Repeated
  evaluation at a stationary clock cannot apply another count.
- On arm64 the candidate enum and the previous optional scalar both have a
  16-byte stride. Each stored range takes 16 bytes of element payload. The
  partial benchmark uses at most two live ranges (32 bytes of element
  payload). An alternating candidate pattern can require up to 8,192 ranges
  (128 KiB of element payload). An exact fixed bitset would cap the payload
  at 2 KiB and handle fragmentation better, at the cost of processing up to
  256 machine words per partial-state rotation and consensus. Ranges were
  chosen for the common singleton, sparse, and contiguous cases. These
  figures exclude array headers, spare capacity, temporary allocations and
  process memory.
- The native arm64 Debug build and complete Xcode 27.2 suite passed on the
  WORK Mac. The baseline was 229 tests in 45 suites (334 executions).
  Phase 4B.3 passed 232 tests in 45 suites (341 executions), with zero
  failures or skips. Xcode result identifiers confirm all 229 baseline
  tests and all 153 parameterised baseline cases remain. The existing
  supply-fault, ratio/rollover, and wired clock fixtures are unchanged.
  The CD4060 suite adds seven executions covering stationary X/Z RESET at
  zero and eight, reset and count branches at a falling edge, sparse
  consensus and recovery, candidate wrap/merge, X/Z clock samples under
  the existing edge policy, and resolved pulls and contention in both
  power modes. The wired Explicit Power regression still checks exact
  transitions for 32,768 Hz → 2 Hz on pin 3 → 1 Hz on the CD4027.
- The existing Swift actor-isolation warnings originate in the
  CD4510/CD4516 uncertainty test parameters. Separately, Xcode reports
  that App Intents metadata extraction was skipped because there is no
  framework dependency.

#### Phase 4B.3 wall-clock benchmark

Both versions used the same native arm64 Debug configuration and fixture
on the WORK Mac with Xcode 27.2 and parallel testing disabled. Each
workload used one warm-up and five measured runs. The table shows
monotonic wall time in milliseconds as median [minimum–maximum].
Timing excludes fixture creation and initial reset.

| Workload | Before (ms) | After (ms) | Median change |
| --- | ---: | ---: | ---: |
| Isolated, definite | 376.72 [373.54–378.32] | 393.57 [391.84–396.56] | +4.5% |
| Isolated, partially uncertain input schedule | 357.31 [356.86–358.00] | 567.63 [560.15–568.83] | +58.9% |
| Isolated, fully unknown | 353.60 [349.73–359.31] | 371.45 [370.64–372.25] | +5.0% |
| Wired CD4060 → CD4027 | 1,481.52 [1,465.44–1,509.68] | 1,467.86 [1,461.37–1,477.76] | −0.9% |

Each isolated run feeds 262,144 HIGH/LOW cycles directly into the model
(524,288 evaluates). The definite case starts at zero. The fully unknown
case starts fresh with RESET LOW. The partial case repeats 256-cycle blocks
with RESET HIGH on cycle 0, X on cycles 8–23 inclusive, and LOW otherwise
(zero-based). Both versions see the same inputs. The old version discarded
all state at the first X, which explains why the partial workload compares
different amounts of useful work. The definitive isolated path showed a
repeatable slowdown in this sample. The wired timing ranges overlap.
Caching divider output-pin lookups was also tried and dropped after it
increased the isolated definite median to 404.71 ms.

The wired workload uses the deterministic Explicit Power fixture and
services exactly one simulated second (65,536 half-period events) with
the virtual time source held fixed. Median host throughput was about
44,236 events/s before and 44,647 events/s after, or 0.675 and 0.681
simulated seconds per wall second. This measures a Debug build of the
whole clock circuit on this host. The simulated input and output remain
32,768 Hz, 2 Hz and 1 Hz regardless of host throughput. The benchmark
neither measures a Release build nor compares against a physical chip's
maximum switch rate. Oscillator analogue behavior, supply ramps and
ripple delays are outside this phase. Uncertain clock transitions remain
Phase 5 work.

### CD4017/CD4026 Phase 4C.1 verification on 28 November 2026

- The digital models follow the TI CD4017BE and CD4026BE top-view PDIP-16
  terminal diagrams. CD4017B clocking and carry follow SCHS027C (February
  2004), pp. 1–2, including the pin 13 clocking footnote and Fig. 2.
  CD4026B clocking, display gating, display-enable output, carry and ungated
  c follow SCHS031B (July 2003), pp. 1 and 3, Figs. 1 and 3.
  [TI CD4017B datasheet](https://www.ti.com/lit/ds/symlink/cd4017b.pdf) ·
  [TI CD4026B datasheet](https://www.ti.com/lit/ds/symlink/cd4026b.pdf)
- The Phase 4A audit found that X or Z reset discarded the entire count.
  Both chips now retain a bounded set of whole counts (0–9). An asserted
  reset selects zero and an X or Z reset adds zero to the ordinary outcome.
  Each decoded output and carry is driven by consensus. Carry is HIGH at
  counts 0–4. At stationary count 1 with X or Z reset, CD4017 Q0/Q1 are X
  and Q2–Q9 are LOW. With display enabled, CD4026 b/c are HIGH, g is LOW,
  and a/d/e/f are X. Both carries and ungated c are HIGH. DE LOW blanks
  all gated segments, including ones whose decoded values are X. DE OUT
  drives the resolved binary enable level or X when the input is X or Z.
- A LOW-to-HIGH CLOCK with stable LOW inhibit advances once. With stable
  X or Z inhibit it produces count-or-hold. A HIGH-to-LOW inhibit with
  CLOCK held HIGH also advances once. Each evaluation records the resolved
  pin samples, so repeated passes at the same levels consume no extra
  edges. Transitions through X/Z on clock-capable pins and samples where
  both clock-capable inputs change together have no qualified edge in this
  phase. Their timing and ordering are deferred to Phase 5. Candidate
  counts preserve correlations across outputs within a chip. Resolved X/Z
  carries no cross-pin or cross-chip correlation metadata.
- Explicit Power uses the existing ideal +5 V/GND supply validation.
  Automatic Power assumes valid supply. Fresh state and restoration after
  invalid supply start with all ten counts possible. The model uses settled
  logic levels and has no propagation, supply ramp, analogue input or
  timing tolerance parameters. Fixtures compare settled logic states
  exactly and exercise both power modes, weak pulls, strong contention,
  wired MAN74A outputs, and a carry-to-clock cascade in both registration
  orders.
- Native arm64 Debug build and the full Xcode 27.2 suite passed on the
  WORK Mac using a copy of the local working tree. Baseline: 232 tests,
  45 suites, 341 executions. Phase 4C.1: 236 tests, 46 suites, 351
  executions. Both runs had zero failures and zero skips. All 232 baseline
  test identities and 159 parameterized cases were retained. Baseline
  fixtures are unchanged. In the new resolved-reset fixture, the strong
  LOW driver is released before the weak HIGH pull recovers zero. An
  earlier run exposed the incorrect fixture expectation with both drivers
  active.
- Existing build warnings are the Swift actor-isolation diagnostics in
  the CD4510/CD4516 uncertainty test parameters on full compilation, and
  skipped App Intents metadata extraction without a framework dependency.

### CD4518/CD4520 Phase 4C.2 verification on 28 November 2026

- The TI CD4518BE and CD4520BE top-view PDIP-16 terminal diagram and
  truth table (SCHS076D, March 2004, p. 1) give CLOCK/ENABLE/RESET on
  pins 1/2/7 and 9/10/15, Q1–Q4 on 3–6 and 11–14 (LSB first),
  and shared VSS/VDD on 8/16. A rising CLOCK with ENABLE held HIGH
  or falling ENABLE with CLOCK held LOW increments the addressed half.
  TI specifies ripple cascading from Q4 to the next half's ENABLE
  with its CLOCK tied LOW.
  [TI CD4518B/CD4520B datasheet](https://www.ti.com/lit/ds/symlink/cd4518b.pdf#page=1)
- Each half stores its own whole-count candidates (0–9 or 0–15) and
  resolved CLOCK/ENABLE history. RESET HIGH asynchronously selects zero.
  Resolved RESET X or Z adds zero to the ordinary outcome. Each Q bit
  drives the consensus across candidates. The Phase 4A cases now give
  CD4518 {0,8} / X000 and CD4520 {0,15} / XXXX at a stationary clock.
  Releasing CD4520 RESET to LOW and counting once gives {0,1} / 000X.
- A clean rising CLOCK or falling ENABLE with its other input stable at
  X or Z retains both count and hold. Recording both input samples,
  including during reset, prevents repeated settling from consuming
  the same event. Phase 5 will address edges through X/Z and ordering
  when both clock-capable pins change in the same resolved sample.
  Receiver uncertainty carries no cross-pin or cross-package correlation.
- Shared Explicit Power validation uses ideal +5 V and GND. Invalid
  supplies invalidate both halves and drive X. Fresh and restored halves
  start with every count possible until controls constrain them.
  Automatic Power assumes ideal supply. The ideal digital model omits
  propagation and setup/hold timing, analogue thresholds, supply ramps
  and output loading.
- Wired engine fixtures compare exact settled logic levels with ideal
  rails or Automatic Power. They cover both halves, both rollovers,
  dominant reset, both definite edge mechanisms, stable X/Z gating,
  weak pulls, contention, repeated settling, invalid rails, restoration
  at either clock level, and Q4-to-ENABLE cascading in both registration
  orders. Existing fixtures were unchanged. The first run of the new
  reset fixture incorrectly expected the zero candidate to stay at zero
  after RESET release and a valid edge. The corrected fixture advances
  both candidates.
- The WORK Mac native arm64 Debug build and full Xcode 27.2 suite passed.
  Baseline on a copy of the original working tree: 236 tests, 46 suites,
  351 executions. Phase 4C.2 in the canonical checkout: 240 tests,
  47 suites, 367 executions. Both runs had zero failures and zero skips.
  The Xcode result bundles confirm all 236 baseline test identities and
  169 parameterized baseline executions still pass. Existing Swift
  actor-isolation and App Intents build warnings remain.

### CD4027 Phase 4D verification on 28 November 2026

- The model follows the Texas Instruments CD4027BE top-view PDIP-16
  terminal diagram and function table in SCHS032D (July 2021), §§5 and
  8.2. Unit A uses Q/Q̅/CLK/RESET/K/J/SET on 1–7. Unit B uses the
  same order on 15–9. Both share VSS on 8 and VDD on 16.
  [TI CD4027B datasheet](https://www.ti.com/lit/ds/symlink/cd4027b.pdf#page=9)
- Each unit stores a set of at most three correlated (Q, Q̅) pairs
  and its own clock history. The valid pairs are (LOW, HIGH),
  (HIGH, LOW), and (HIGH, HIGH). Asserted asynchronous controls take
  priority. The resolved X and Z input levels each admit both binary
  possibilities. Each output drives the consensus across candidates.
  SET HIGH with RESET X/Z produces (HIGH, X). RESET HIGH with SET X/Z
  produces (X, HIGH).
- Releasing one of two asserted controls leaves the other in command.
  A possible simultaneous release of both asserted controls admits
  either normal state, including when a rising clock is observed in
  that sample. With both asynchronous controls inactive, JK samples
  only on an adjacent resolved LOW-to-HIGH clock transition. From
  LOW, J determines the next Q. From HIGH, inverted K determines it.
  An unknown prior state stays unknown in toggle mode and a later
  definite set or reset can recover certainty.
- Fresh and restored units start with both complementary pairs
  possible and no clock history. Explicit Power requires the shared
  ideal +5 V and GND rails. Missing or incorrect rails clear both
  units and the engine drives X. Automatic Power assumes ideal rails.
  The model uses settled digital logic only. It omits analogue input
  thresholds, propagation delay, output loading, supply ramps, pulse
  width and setup/hold effects. Uncertain clock transitions and
  ordering of simultaneous input changes are deferred to Phase 5.
  Receiver uncertainty has no cross-pin correlation.
- Wired tests compare exact settled levels under ideal Explicit and
  Automatic Power. They exercise both physical units, the full JK
  truth table, unknown and floating controls, recovery, weak pulls,
  contention, downstream inversion, repeated settling, and restoration
  with clocks at different levels. The minutes/hours selector fixture
  uses clean pulses and complementary select outputs. The existing
  deterministic CD4060 fixture still verifies 32,768 Hz → 2 Hz → 1 Hz
  at exact simulated half-cycle boundaries. No existing fixture needed
  adjustment.
- The WORK Mac native arm64 Debug build and full Xcode 27.2 suite
  passed in the canonical checkout. Baseline: 240 tests, 47 suites,
  367 executions. Phase 4D: 246 tests, 48 suites, 378 executions.
  Both runs had zero failures and zero skips. The Xcode results
  preserve all 240 baseline test identities and 185 parameterized
  executions. Existing build warnings were left in place.

### CD4511/CD4543 Phase 4E verification on 28 November 2026

- The models follow Texas Instruments CD4511BE and CD4543BE top-view
  PDIP-16 terminal assignments, logic diagrams and output truth tables.
  Both use VSS 8 and VDD 16. CD4511 A–D are 7/1/2/6, LT/BI/LE are
  3/4/5, and a–g are 13/12/11/10/9/15/14. CD4543 A–D are 5/3/2/4,
  LD/PH/BI are 1/6/7, and a–g are 9/10/11/12/13/15/14.
  The tables differ on 6 and 9. The CD4511 omits segment a for 6 and d
  for 9. The CD4543 includes those segments. The previous definite
  glyphs match the TI rows. Codes 10–15 blank on both parts.
  [TI CD4511B SCHS072B, Fig. 8 and truth table](https://www.ti.com/lit/ds/symlink/cd4511b.pdf#page=4)
  · [TI CD4543B SCHS086D, Fig. 1](https://www.ti.com/lit/ds/symlink/cd4543b.pdf#page=2)
  · [CD4543B truth table](https://www.ti.com/lit/ds/symlink/cd4543b.pdf#page=5)
- Each latch stores up to 16 whole BCD words. Resolved X or undriven Z
  at a receiver admits both binary levels. CD4511 LE LOW and CD4543
  LD HIGH replace the candidates with the current input words. Hold
  retains the set. An ambiguous latch admits both hold and transparent
  outcomes. Re-evaluating unchanged inputs gives the same set. Fresh
  state and power loss admit all 16 words, so restoring in hold
  with overrides inactive drives X until transparent sampling recovers
  data. Explicit Power requires the existing +5 V and GND rail identities.
  The engine drives X for missing or incorrect rails. Automatic Power
  assumes valid rails.
- Output logic follows the Phase 4A audit and TI control priority. On
  CD4511, LT LOW forces all HIGH ahead of BI LOW blanking. CD4543 BI
  HIGH blanks, with PH HIGH inverting even the blanked levels. The
  model applies the full override rule in each possible output branch
  and drives per-segment consensus. Output overrides leave state
  selection to the latch control, including transparent sampling
  during lamp test or blanking.
- The digital model uses settled pin levels and ideal outputs.
  Candidate words preserve correlations within stored BCD values.
  Different uncertain receiver pins are expanded independently, even
  when they share a net or upstream source. This can introduce extra
  candidates and X outputs. Physical setup/hold, propagation delay,
  supply ramps, output loading, and analogue LCD behavior are outside
  the model. Uncertain clock transitions remain deferred to Phase 5.
- Wired fixtures use ideal +5 V/GND in Explicit Power and ideal
  assumed rails in Automatic Power. The truth-table sweep compares
  exact logic levels for all 16 words on both drivers, with both PH
  levels on CD4543. The five added tests also cover partial BCD,
  latch and override X/Z, repeated settling, recovery, weak pulls,
  contention, MAN74A/MAN72A illumination and downstream inversion.
  The existing SevenSegmentPowerTests checker now accepts mixed
  HIGH/LOW/X levels. Existing fixture inputs and expected behavior were
  preserved. The Phase 3 rail-loss, hold and transparent restoration
  tests, wired Workbench archive tests, and clock regressions passed.
- The WORK Mac native arm64 Debug build and full Xcode 27.2 suite
  passed in the canonical checkout. The baseline reproduced 246 tests,
  48 suites and 378 executions. Phase 4E passed 251 tests, 48 suites
  and 394 executions. Both runs had zero failures and zero skips.
  Xcode result identifiers confirm that all 246 baseline tests and
  195 baseline parameterized executions still pass. The existing
  App Intents metadata warning remains.

Read this status file and inspect the current working tree when resuming development. Update the document after significant features, architectural decisions, or confirmed issues.


## Mechanical switch model

- **Source and terminal roles.** The [official KiCad Switch library](https://kicad.github.io/symbols/Switch)
  defines these as generic components. Pin positions and roles follow the installed
  KiCad 10 `Switch.kicad_sym` (library format 20251024), specifically the
  `SW_Push` and `SW_SPDT` symbol pin entries. The physical view is a generic
  top-view illustration with the same numbered attachment points. There is no
  manufacturer, part suffix, footprint, datasheet rating, or SPICE model for
  these designations.
- **Digital operation.** In both workbench power modes, a closed contact joins
  its two nets into one digital electrical island. Strong and weak drivers,
  contention, and high impedance use the existing net resolver. The open
  contact contributes no connection or drive. SW_Push joins 1 to 2 during a
  press and opens on release or cancellation. SW_SPDT starts connected 2–1
  and alternates between 2–1 and 2–3. Archives and clipboard copies preserve
  the maintained position. A push button reopens or pastes released.
- **Electrical limits.** Contacts are ideal open circuits or ideal shorts in
  the digital model. There are no numeric contact parameters or part ratings.
  This model omits contact resistance, leakage, bounce, switching transients,
  and break-before-make timing. External pull resistors use the existing
  weak-driver approximation in digital circuits. Their resistance does not
  set an analogue voltage or current in this path.
- **DC and timing.** The discrete DC solver uses fixed wire nets and has no
  switch stamps. A DC device region touching a mechanical switch terminal's
  wire net uses the digital fallback in either contact position, including
  when the shared net is a supply rail. Independent eligible regions can
  still solve. The existing global DC bypass for CD4051/52/53 remains in
  effect. NE555 timing topology recognition still uses fixed wires, so
  switched timing networks remain outside the supported RC model.
- **Verification fixtures.** Workbench tests use ideal +5 V and GND logic rails.
  They check both directions of push-button conduction, high impedance at rest,
  contention, and exact HIGH/LOW readings with an external 470 Ω pull-up or
  pull-down (the default resistor value, used in the digital approximation).
  They also cover KiCad pin mapping, rotation, archives, clipboard copies, and
  an independent DC LED branch with a switch present.

## SN74LS90, SN74LS92 and SN74LS93 ripple counters

The 74LS Series TTL family includes TI SN74LS90N, SN74LS92N and SN74LS93N
in top-view PDIP-14. The model follows [TI SDLS940A, revised March 1988](https://www.ti.com/lit/ds/symlink/sn74ls90.pdf).
Page 1 gives pinouts and cascade wiring. Pages 3–4 specify the control
truth tables, settled output sequences and clock polarity. Pages 8–9 give
the SN74LS electrical limits and page 10 shows the falling-edge relationship.

| Part | R0(1)/R0(2) | R9(1)/R9(2) | QA/QB/QC/QD | NC |
|---|---|---|---|---|
| SN74LS90N | 2/3 | 6/7 | 12/9/8/11 | 4, 13 |
| SN74LS92N | 6/7 | — | 12/11/9/8 | 2, 3, 4, 13 |
| SN74LS93N | 2/3 | — | 12/9/8/11 | 4, 6, 7, 13 |

All three use pin 14 CKA, pin 1 CKB, pin 5 VCC and pin 10 GND.
Clock A toggles QA and clock B steps its own ÷5, ÷6 or ÷8 sequence,
respectively. Connect QA to CKB and clock CKA for ÷10, ÷12 or ÷16.
In QD–QA bit order, the LS92 cascaded sequence is 0–5 then 8–13.
On the LS90, QD to CKA with the external clock on CKB produces the
bi-quinary sequence and a divide-by-ten square wave on QA. Both R0 inputs
HIGH reset to zero asynchronously. On the LS90, both R9 inputs HIGH set
the outputs to nine and take priority over R0. Drive at least one input of
each inactive control pair LOW. NC pins have no internal connection.

The simulator uses ideal digital HIGH/LOW drivers and the shared 5 V DC
interface. The guaranteed SN74LS input limits, VIL max 0.8 V and VIH min
2.0 V, are the solver-to-logic thresholds for solved input voltages. The
intervening region is X. The TI limits apply over the SN74LS recommended
4.75–5.25 V supply and 0–70 °C range. The workbench supplies ideal 5 V and
ground in Explicit Power mode and assumes valid supply in Automatic Power
mode. Temperature and supply variation are outside the model. Count state
starts with every legal package state after power loss or archive reopen.
A definite reset or preset establishes a known count. Floating or X
clocks break edge qualification. Resolved X and Z on control inputs
admit both binary levels. A known LOW masks the other input of its pair.
TTL floating-input bias, output voltage drop, input and output current,
fan-out, propagation delay, ripple glitches, minimum pulse widths and
setup time are omitted.

Validation fixtures use ideal logic sources with settled observations
after each half-cycle. At ideal 5 V, the expected control and sequence bits
match TI page 3 exactly. Separate DC-divider fixtures exercise the input
regions at 0.79, 0.81, 1.99 and 2.01 V (fixture voltage tolerance 1 µV).
The physical DIP and built-in schematic share pin numbers with the
`74xx:74LS90`, `74xx:74LS92` and `74xx:74LS93` KiCad netlist mappings
and existing Workbench archive format.

### Phase 4F verification on 28 November 2026

- Each candidate stores the A state and the B sequence index together.
  The bounds are 10, 12 and 16 legal states for the LS90, LS92 and LS93.
  Reset, preset and normal counting contribute whole-package outcomes.
  A definite R9 pair on the LS90 overrides R0. Both clock inputs are
  sampled during asynchronous control, and only the branch with both
  controls inactive advances on a definite falling edge. The output
  pins drive their individual consensus across the candidate states.
- The Phase 4A audit cases now produce QD–QA `X00X` for the LS90 with
  R0 HIGH/HIGH and R9 HIGH/X or HIGH/Z, `00X0` for the LS92 from
  `0010`, and `000X` for the LS93 from `0001`, both with R0
  HIGH/X or HIGH/Z. Further settled steps exercise definite recovery,
  separate falling edges and repeated settling. The new input fixtures
  also exercise weak HIGH, strong LOW and strong contention.
- Phase 4F added four test identities with 20 parameterized executions
  to the existing SN74LSCounterTests suite. The new fixtures use ideal
  clock and control sources, compare exact settled pin levels, and run
  the ambiguity and rail cases in both power modes. The two-package
  cascade fixture checks both registration orders in Explicit Power
  mode. Existing fixtures, inputs and expectations were retained,
  including the bi-quinary hookup, DC thresholds, KiCad pin mapping,
  rotation and archive round-trip. No baseline fixture adjustments were
  needed.
- The WORK Mac native arm64 Debug build passed in the canonical checkout
  using Xcode 27.2. Before edits, the full suite passed 251 tests across
  48 suites and 394 executions. The final run passed 255 tests across
  48 suites and 414 executions. Both had zero failures and skips. Xcode
  result identifiers verified all 251 baseline tests and 211
  parameterized executions. The existing App Intents metadata warning
  remains.
- The model follows settled receiver values. When one unresolved source
  affects several control receivers, the model may admit extra outcomes
  across the separate pairs. Output consensus can also hide clock edges
  that are only possible in some candidates. Uncertain clock transitions
  and simultaneous edge ordering remain Phase 5 work. Physical ripple
  delays and TTL floating-input bias are outside this model.

## Phase 4G integration verification on 28 November 2026

### Verification

- WORK Mac, native arm64, Xcode 27.2 (27B52). The pre-edit Debug
  baseline reproduced 255 passing tests in 48 suites and 414 executions
  with zero failures and skips. Xcode reported 231 parameterized cases
  belonging to 72 test identities.
- The final full Debug suite passed 262 tests across 50 suites and 435
  executions with zero failures and skips. Xcode result identifiers
  confirmed that all 255 baseline test identities and all 231 baseline
  parameterized cases still pass. Phase 4G adds seven tests and 21
  executions. The native arm64 Debug app build and Release app build
  both succeeded.
- The first focused run expected an unknown CD4510 count on reopening.
  The existing model initializes a fresh CD4510 to zero. The fixture
  now verifies the established zero startup against a live count of 12
  before saving. The clock is HIGH and running before saving and starts
  LOW and paused after opening. Both modes pass with this
  fixture correction.

### Wired coverage

- A scheduled ideal 32,768 Hz Workbench clock drives CD4060 pin 11.
  CD4060 Q14 drives a toggle-connected CD4027, whose Q clocks both
  CD4510s. The ones carry drives the tens carry-in. CD4511/MAN74A shows
  ones and CD4543/MAN72A shows tens. The fixture checks the sample
  immediately before and exactly at each divider edge from 0.25 to
  1.25 simulated seconds, with JK rising edges at 0.25 and 1.25 s.
- A separate common-clock fixture with direct, immediate clock steps
  checks every displayed digit on both clock phases through 00–99–00
  up and 00–99–00–99 down, in Explicit and Automatic Power and both
  upstream-first and downstream-first registration. The CD4543 path
  exercises its distinct 6 and 9 glyphs. Explicit Power removes and
  restores the ones counter supply while the decoder remains powered.
  The state stays indeterminate until reset, after which both digits
  read 00 and one pulse displays 01.
- SN74LS90/92/93 exercises separate falling-edge A and B clocks and
  QA-to-CKB cascades (divide by 10, 12 and 16). The separate LS90
  bi-quinary hookup checks divide by ten and equal HIGH/LOW intervals
  on QA. The CD40106 → LS90 → CD4511 → MAN74A fixture verifies ideal
  digital CMOS/TTL interoperability in both directions. This is a
  digital model result. Physical voltage, fan-out, current and
  electrical compatibility are outside its coverage.
- With the ripple link isolated and both LS90 clock pins held at
  settled definite levels, the reset/preset case propagates X00X in
  QD–QA order to CD4511. Segments b and c stay definitely lit, and
  the remaining segments are X across repeated settles. Both power
  modes and registration orders are covered.
- The archive check round-trips the Workbench JSON for the accelerated
  chain in both power modes. It compares the saved configuration bytes
  after reopen and checks clock frequency, clock phase, running status,
  count initialization and the first count after reset.

### Throughput

The timed workload is one simulated second (65,536 source half-period
events) through the full two-display circuit in Explicit Power. Both
builds use the same fixture and virtual clock with no scope probes and
parallel testing disabled. Debug uses the project's default test settings.
The Release benchmark keeps the Release optimization settings and adds
`ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES` for that invocation. The
first Release test invocation stopped at compilation because the default
Release module does not support `@testable import`. A separate standard
Release app build uses the project defaults. Each configuration runs a
warm-up and five
measured trials, each with a newly wired and reset circuit. Wall time
uses a monotonic clock and excludes setup, reset and test launch. The
real-time ratio is simulated seconds per wall second.

| Build | Median wall time [min–max] | Median source events/s | Real-time ratio |
| --- | ---: | ---: | ---: |
| Debug | 5.4728 s [5.3979–5.4855] | 11,975 | 0.183× |
| Release | 0.6863 s [0.6805–0.6877] | 95,499 | 1.457× |

- Debug runs in seconds were 5.4855, 5.4728, 5.3979, 5.4417, 5.4827.
- Release runs in seconds were 0.6863, 0.6877, 0.6816, 0.6869, 0.6805.

The earlier Phase 4B.3 wired benchmark had the same source rate and
event count but a smaller circuit ending at CD4027. No performance
comparison is made across those workloads.

To repeat the measurement, temporarily add the following wrapper to the
test target and select only `CMOS4000SimulatorTests/Phase4GBenchmarkRunner`
in native arm64 Xcode tests. Set the configuration to Debug, then Release,
and disable parallel testing for both. Pass the Release overrides above
to its `xcodebuild test` invocation. Remove the wrapper before running
the full correctness suite.

```swift
import Testing

@MainActor
struct Phase4GBenchmarkRunner {
    @Test func measure() throws {
        let seconds = try Phase4GThroughput.measure()
        print("PHASE4G_BENCHMARK_SECONDS \(seconds)")
    }
}
```

### Working tree and checkpoint

- Phase 4G adds `CMOS4000SimulatorTests/Phase4GIntegrationTests.swift` and
  appends this entry to `PROJECT_STATUS.md`. The working tree still
  contains the 12 previously modified tracked files and eight previously
  untracked files, plus the new test file. No existing test source was
  edited during Phase 4G.
- `main` and `origin/main` were 0 ahead and 0 behind at
  `af137a722c949e4d180c15ccb910ff69deb88842`, also confirmed against
  GitHub's `refs/heads/main` with a read-only query. Local edits and
  untracked files are pending. Neither a commit nor a push was made.
- No integration defect or verification blocker was observed. Existing
  Xcode warnings remain, including App Intents metadata extraction
  and Swift Testing actor-isolation warnings in prior fixtures.
  Recommended checkpoint is the verified Phase 4G working tree.
  Review and preserve that checkpoint before moving to Phase 5
  uncertain clock transitions or switching Macs.

## Phase 5B.1 clock history foundation on 28 November 2026

### Sample identity and receiver history

- `SimulationCore/CorrelatedClockHistory.swift` defines a resolved receiver
  sample with a non-wrapping, strictly increasing ordinal scoped to one
  clock stream. The producer assigns a new ID for a causally relevant
  resolved receiver update, even if the symbol stays X or Z. A derived
  update can have its own ID at the same simulated time. Settling the same
  event reuses its ID and level. Unrelated activity produces no new clock
  sample. Repeated and stale deliveries skip the boundary callback.
- Startup and explicit history invalidation are uninitialized. A fresh first
  sample establishes binary history without an edge, including when it
  admits both LOW and HIGH. Invalidation uses a caller-supplied device
  state and retains the last consumed ID so the old event cannot initialize
  restored history. A live X or Z admits both binary levels and can produce
  a hold, rise or fall according to the preceding binary level.
- Each candidate carries its previous binary clock level and its device
  state. The boundary callback uses the controls captured for that sample
  and can return alternative device states. LOW→X/Z→HIGH admits one modeled
  rise and HIGH→X/Z→LOW one modeled fall under uninterrupted enabled
  sampling. A return to the origin can preserve both the hold history and
  the pulse history. These counts describe the sampled digital model.
- Equivalent state/level pairs merge on each sample. For a finite domain
  of N device states there are at most 2N live pairs after initialization.
  The caller owns that finite domain. A single candidate uses inline
  storage and requires no candidate set on a definite, single-successor
  transition.

### Native verification

- The canonical WORK Mac checkout was clean at
  `06bb45b8657a7b113e19732f74874bf67b5507fb` before edits. Local main, cached
  origin/main and live GitHub main matched. The Xcode 27.2 (27B52) native
  arm64 Debug baseline passed 262 tests in 50 suites and 435 executions,
  with zero failures or skips.
- Phase 5B.1 passed the native arm64 Debug app build and full suite.
  The updated suite passed 269 tests in 51 suites and 463 executions,
  with zero failures or skips. Xcode result IDs confirmed retention of
  all 262 baseline tests, 50 suites and 251 parameterized executions.
  The new suite adds seven tests and 28 executions, 24 parameterized.
  Xcode emitted the existing App Intents metadata warning.
- The focused suite covers all 16 resolved transitions, X and Z bridge and
  return histories in both directions, mixed and repeated symbols,
  caller-supplied sample boundaries, stale delivery, control snapshots,
  override precedence, invalidation, bounded merging and the singleton
  path. A fixture feeds resolved receiver observations from the existing
  net resolver with strong contention, a weak pull and undriven Z.

### Integration limits and next migration

- The producer contract is exercised with fixture-supplied IDs. Production
  engine event generation, control-only updates, shared-net correlation
  across devices, and derived-event ordering are deferred. The existing
  ClockEdgeDetector, chip models, scheduler batching and convergence code
  retain their current behavior.
- Proposed Phase 5B.2 starts with CD4510 and CD4516. Define where the engine
  emits receiver sample IDs and snapshots pre-edge carry and control inputs.
  Preserve asynchronous reset/preset priority and invalidate on power loss,
  then verify wired common-clock carry and uncertain-clock histories in
  both power modes and registration orders.

## Phase 5B.2 CD4510 and CD4516 on 28 November 2026

### Receiver behavior and supported provenance

- CD4510 and CD4516 now retain each possible count with its previous binary
  clock level in `CorrelatedClockHistory`. Equivalent pairs merge, so there
  are at most 20 pairs for CD4510 and 32 for CD4516. Definite controls and a
  single count/clock pair use the single-successor path without a candidate
  set. The receiver's increasing sample ordinal survives explicit power
  failure. Startup and the first powered observation after failure establish
  binary history without an edge, and the history rejects consumed and
  stale ordinals.
- Supported clock observations are the level at pin 15 when the receiver
  evaluates, and digital driver provenance when that level is X or Z.
  A different driver or drive at the winning tier can distinguish X from a
  previous X. A floating Z records the connected drive-capable pins, so a
  change in those connections can distinguish Z from a previous Z. An
  external source with an independently identified event can call
  `Pin.publishClockDrive` and settle at that boundary to distinguish
  consecutive X or Z deliveries from the same driver. Ordinary sources
  continue to use `drive`. Stable observations, shadowed weak drivers under
  a strong drive, and unrelated nets leave the receiver sample unchanged.
  Provenance compares driver identities and values independently of pin
  traversal order.
- Control-only changes update asynchronous state and carry while retaining
  each branch's previous binary clock. RESET takes priority over PE.
  CD4510 retains the existing hold policy for each invalid BCD preset
  completion. Carry consensus is computed from the same control branch
  that generated each count. On a directly shared clock with settled
  controls, both receivers use pre-edge carry from the current resolved pass.
  [TI CD4510B/CD4516B, SCHS071B, July 2003](https://www.ti.com/lit/ds/symlink/cd4510b.pdf)

### Event limits

- The receiver observes the final inputs for each evaluation pass. Multiple
  source mutations before the same resolution boundary are observed together.
  An ordinary repeated `drive(X)` or `drive(Z)` carries no event marker.
  Same-symbol changes hidden by an upstream model's unchanged output
  consensus, same-symbol analog/DC changes, and changes inside passive
  topology with identical relevant driver observations have no independent
  receiver provenance. The DC path contributes resolved level changes.
- Independently tracking a shared uncertain clock in two receivers does not
  correlate their choices across chips or with uncertain carry. The common
  clock guarantee above is for definite shared-clock edges with settled
  controls. Existing pass order governs derived clock/control arrival.
  Scheduler ordering, convergence, and the other chip models remain on
  their existing paths.

### Native verification

- On the canonical WORK Mac checkout at
  `06bb45b8657a7b113e19732f74874bf67b5507fb` with the local Phase 5B.1
  changes present, Xcode 27.2 (27B52) reproduced **269 tests in 51 suites,
  463 executions, zero failures and zero skips** in native arm64 Debug.
- The Phase 5B.2 native arm64 Debug app build and full suite passed
  **275 tests in 51 suites, 491 executions, zero failures and zero skips**.
  Comparing Xcode result identities confirmed retention of all 269 baseline
  tests, all 51 suite identities and all 275 parameterized executions. Six
  new tests add 28 parameterized executions.
- Wired fixtures cover X/Z bridges and returns, mixed and distinct
  same-symbol samples, repeated settling, separate-net activity and masked
  weak pulls, controls at both sample boundaries, asynchronous override
  and release, contention, LOW/HIGH/X/Z startup and restoration, and up/down
  decimal and binary common-clock cascades in both registration orders.
  Both Automatic and Explicit Power are exercised. The Phase 5B.1
  stale-delivery regression remains in the full suite.

## Phase 5B.3 CD4029 on 28 November 2026

### Clock history and device behavior

- CD4029 now uses the production pin-15 clock provenance and
  `CorrelatedClockHistory` used by CD4510 and CD4516. Each candidate pairs a
  four-bit count with its preceding binary clock level. Equivalent pairs
  merge, bounding the initialized history at 32 pairs. A definite clock
  with one count and a valid single successor uses inline history storage.
  The first powered sample, including X or Z, seeds the clock history
  without an edge. Explicit power loss invalidates the count and clock
  history while retaining the monotonically increasing receiver ordinal.
- With continuously enabled counting, LOW → X/Z → HIGH gives one rising
  edge. LOW → X/Z → LOW retains the possible hold and pulse paths. At each
  sample CD4029 uses the resolved controls for that boundary. A control-only
  update applies asynchronous JAM and updates carry with the existing clock
  histories. Repeated settling and unrelated activity do not consume a
  clock sample. A changed driver at the winning tier, a changed potential
  driver on a floating net, or an explicit `Pin.publishClockDrive` can
  distinguish consecutive samples with the same X or Z symbol.
- The ideal digital model retains the TI CD4029BE PDIP-16 pinout, the
  asynchronous active-HIGH PE/JAM behavior, binary and decade up/down
  counting, and active-LOW CI and CO. Each successor contributes carry
  using its own mode, direction and CI. Common-clock stages on a definite
  edge use pre-edge carry with settled controls in either registration order.
  The existing non-BCD decade policy still accepts any JAM value. An
  enabled transition from 10 through 15 admits all 16 results in that
  clock branch. A held invalid decade count preserves its Q bits and gives
  X for CO when CI is LOW.
  [TI CD4029B datasheet, SCHS034C, p. 1 and Fig. 17](https://www.ti.com/lit/ds/symlink/cd4029b.pdf)

### Native verification

- On the canonical WORK Mac checkout at
  `06bb45b8657a7b113e19732f74874bf67b5507fb`, with local Phases 5B.1–5B.2
  present, Xcode 27.2 (27B52) reproduced **275 tests in 51 suites,
  491 executions, zero failures and zero skips**.
- The Phase 5B.3 native arm64 Debug app build and full suite passed
  **280 tests in 51 suites, 513 executions, zero failures and zero skips**.
  Xcode result identities match all 275 baseline tests, all 51 baseline
  suites and all 303 baseline parameterized executions. Five new CD4029
  tests add 22 parameterized executions. Xcode emitted the existing App
  Intents metadata warning.
- New wired fixtures cover X/Z bridges and returns, published and
  driver-set same-symbol samples, repeated settle, unrelated activity,
  control changes at both clock boundaries, clock contention and weak
  pulls, and startup and restoration at LOW/HIGH/X/Z in both power modes.
  Retained CD4029 fixtures cover ambiguous mode, direction, CI, PE and JAM,
  invalid decade transitions, and definite binary and decade rollover and
  up/down cascades in both power modes and registration orders. Fixtures
  compare exact Q/CO logic states with ideal +5 V/GND or Automatic Power.

### Model limits

- Each receiver tracks its own uncertain clock histories. Choices on a
  shared uncertain clock and uncertain carry between chips remain
  independently evaluated. The simulator samples one resolved observation
  per evaluation pass, so source changes batched before resolution can
  collapse into a single sample. Repeated ordinary `drive` calls with the
  same symbol carry no event marker. Same-symbol analog/DC changes and
  provenance hidden by upstream output consensus remain unobservable.
- The existing scheduler determines when derived clocks and controls
  arrive. The model covers digital logic levels and sampled edges.
  Datasheet propagation delays, setup and hold times, and analog
  metastability are outside the model.

## Phase 5B.4 CD4027 on 28 November 2026

### Clock history and device behavior

- Each half uses production clock provenance on pin 3 or 13 and owns its
  own `CorrelatedClockHistory`. Each candidate pairs one of the three
  valid Q/Q̅ pairs (0,1), (1,0), or (1,1) with the preceding binary clock
  level. Equivalent histories merge, bounding each initialized half at
  six candidates. Definite operation with a single candidate and known
  controls uses inline history storage and single-successor transitions.
- With J and K HIGH, LOW → X/Z → HIGH toggles once. LOW → X/Z → LOW
  retains the hold and toggle alternatives. Each possible rising edge
  samples the J/K levels at that boundary. Asynchronous SET and RESET
  override clocked behavior, and simultaneous assertion drives both
  outputs HIGH. A possible simultaneous release admits both normal
  output pairs while retaining the clock levels. Control-only changes
  do not replay a clock sample.
- The first powered observation seeds the history without an edge at
  LOW, HIGH, X, or Z. Explicit power loss invalidates both halves and
  clears their sampled clock levels. Automatic Power continues to ignore
  missing rails. The ideal digital model retains the TI CD4027BE PDIP-16
  pinout and active-HIGH controls.
  [TI CD4027B datasheet, SCHS032D, Figure 5-1, Table 5-1 and §8.2](https://www.ti.com/lit/ds/symlink/cd4027b.pdf)

### Native verification

- Xcode 27.2 (27B52) reproduced **280 tests in 51 suites, 513 executions,
  zero failures and zero skips** on the canonical WORK Mac checkout at
  `06bb45b8657a7b113e19732f74874bf67b5507fb` with local Phases 5B.1–5B.3.
- The native arm64 Debug build and full suite passed **285 tests in
  51 suites, 535 executions, zero failures and zero skips**. Xcode
  result identities retain all 280 baseline tests, 51 suites, and 325
  parameterized executions. Five new tests add 22 parameterized
  executions. The existing App Intents metadata warning remains.
- Wired tests cover both halves, both power modes, boundary changes of
  J/K, asynchronous override and release, X/Z bridges and returns,
  repeated settling, unrelated activity, same-symbol event publication
  and driver replacement, contention, weak pulls, and startup and
  restoration across all four clock symbols. Logic checks use exact
  Q/Q̅ states with ideal +5 V/GND or Automatic Power. One existing test
  now expects a definite reset after its LOW → X/Z → HIGH sequence,
  since J LOW and K HIGH select reset at either possible rising boundary.
- The deterministic 32,768 Hz CD4060-to-CD4027 1 Hz timebase and the
  minutes/hours toggle fixture passed.

### Model limits

- Clock choices are local to each receiver, including both halves on a
  shared uncertain clock. Each pass samples the resolved observation,
  so source changes batched before resolution can collapse into one
  sample. Ordinary repeated same-symbol drives, same-symbol analog/DC
  changes, and events masked by upstream output consensus are invisible.
  The existing scheduler determines clock and control arrival.
- This is an ideal digital model. Propagation delays, setup and hold
  times, and analog metastability are outside its scope.

## Phase 5B.5 CD4060 performance gate on 28 November 2026

### Baseline

- Xcode 27.2 (27B52) reproduced **285 tests in 51 suites, 535 executions,
  zero failures and zero skips** in native arm64 Debug on the canonical
  WORK Mac checkout with local Phases 5B.1–5B.4 present. Xcode result
  identities matched all 285 tests, 51 suites and 347 parameterized
  executions from Phase 5B.4.
- The baseline passed the test of all ten exposed divider outputs through
  the complete 14-bit cycle and into the next in both power modes. It
  also passed the deterministic 32,768 Hz → 2 Hz → 1 Hz transition fixture.
  TI specifies the 14 stages, falling-edge advance, and active-HIGH
  reset for the CD4060BE PDIP-16.
  [TI CD4060B datasheet, SCHS049C, p. 1](https://www.ti.com/lit/ds/symlink/cd4060b.pdf)

### Matched Debug benchmark

The benchmark used the same native arm64 Debug test fixture on the WORK
Mac before and after applying the candidate, with parallel tests disabled.
Each workload used one warm-up and five measured trials. Wall times are
monotonic milliseconds as median [minimum–maximum], excluding fixture
creation and initial reset.

| Workload | Phase 5B.4 baseline (ms) | Migration candidate (ms) | Median change |
| --- | ---: | ---: | ---: |
| Isolated definite | 375.29 [367.18–378.20] | 413.24 [411.99–415.57] | +10.1% |
| Isolated partial RESET | 548.05 [547.16–562.41] | 588.27 [581.91–596.90] | +7.3% |
| Isolated partial clock | 383.78 [379.43–384.54] | 548.22 [545.18–549.01] | +42.8% |
| Isolated fully unknown count | 352.87 [350.13–355.76] | 391.32 [388.37–397.77] | +10.9% |
| Wired CD4060 → CD4027 | 1,686.32 [1,675.58–1,701.12] | 1,734.98 [1,713.35–1,744.60] | +2.9% |

The isolated workloads use 262,144 cycles with two evaluations per cycle.
Definite and fully unknown use HIGH/LOW with RESET LOW, starting from
zero or a fresh unknown count, respectively. Partial workloads repeat
256-cycle blocks with RESET HIGH on cycle 0. On cycles 8–23, partial
RESET drives RESET X, and partial clock substitutes X for HIGH.
The partial-clock comparison includes new work because the candidate
preserves separate LOW/HIGH histories where the baseline drops
ambiguous edges. The wired Explicit Power fixture services one
simulated second (65,536 half-period events) from a fixed virtual time
source and checks the endpoint states. This measures host Debug
throughput. It leaves Release throughput and physical timing unmeasured.

### Status and limits

- Phase 5B.5 stopped at the performance gate. The candidate stored
  exact ranges in up to two clock-level buckets with a scalar singleton
  path and a full-domain sentinel. It required no shared engine changes
  or per-count candidate objects. The candidate compiled and ran the
  benchmark. Its new correctness cases and final full regression suite
  were withheld at the stop, so the candidate is unverified.
- The benchmark harness was removed and the pre-migration CD4060 source
  restored byte for byte on the canonical checkout. The verified
  Phase 5B.4 local changes are preserved. CD4060 therefore still uses its
  previous ambiguous-clock policy. Oscillator analog behavior, ripple
  timing, and cross-receiver uncertainty remain outside this work.


## Phase 5B.5a CD4060 profiling on 28 November 2026

### Recovery and verification

- Recovered the exact CD4060 source and benchmark harness from the preceding
  performance-gate workspace. The gate run copied those files into the
  checkout and verified both against the saved files before restoration.
  The saved pre-migration source matches the canonical CD4060 byte for byte.
  This run used two isolated snapshots of the canonical WORK Mac checkout at
  `06bb45b8657a7b113e19732f74874bf67b5507fb`, including local Phases
  5B.1–5B.4. The benchmark trees differ in CD4060.swift alone.
- Xcode 27.2 (27B52) passed the native arm64 Debug baseline build and full
  suite with **285 tests in 51 suites, 535 executions, zero failures and
  zero skips**. All 285 test identities, 51 suite identities and 347
  parameterized executions match the prior gate baseline. Both power modes
  passed the ten divider ratios and 14-bit rollover. The deterministic
  32,768 Hz to 1 Hz integration test passed.
- The candidate was used for profiling and its benchmark assertions passed.
  Its migration correctness suite and full regression suite remain pending.

### Matched timing

On the same WORK Mac, the recovered harness ran serially with one warm-up
and five measured trials per workload and variant. Monotonic wall times are
in milliseconds as median [minimum–maximum]. Fixture setup and initial
reset are outside the timer. Debug uses `-Onone`. Release uses whole-module
`-O` and `ENABLE_TESTABILITY=YES`. The benchmark ran natively on arm64 in
both configurations.

The direct-pin fixtures run 262,144 cycles and two evaluations per cycle.
The partial-clock fixture substitutes X for HIGH on cycles 8–23 of each
256-cycle block and resets at block boundaries. It exercises additional
correlated histories in the candidate. The wired Explicit Power fixture
services 65,536 half-period events in one virtual second through the
production Workbench and checks the divider and flip-flop endpoints.

| Build | Workload | Baseline (ms) | Candidate (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 407.32 [405.85–410.19] | 438.38 [436.26–467.02] | +7.6% |
| Debug | partial-reset | 580.50 [579.46–583.80] | 613.88 [610.50–624.32] | +5.8% |
| Debug | partial-clock | 414.27 [409.70–416.66] | 573.04 [572.18–575.40] | +38.3% |
| Debug | unknown | 383.46 [378.71–384.32] | 419.01 [415.93–422.92] | +9.3% |
| Debug | wired | 1,750.87 [1,742.56–1,769.81] | 1,769.97 [1,759.62–1,775.67] | +1.1% |
| Release | definite | 73.41 [73.31–99.95] | 67.61 [67.58–81.90] | -7.9% |
| Release | partial-reset | 80.07 [78.88–81.00] | 81.25 [81.12–82.53] | +1.5% |
| Release | partial-clock | 70.73 [70.61–71.36] | 82.55 [81.49–83.27] | +16.7% |
| Release | unknown | 66.70 [66.52–66.91] | 66.73 [66.51–67.31] | +0.1% |
| Release | wired | 269.22 [260.29–273.89] | 268.83 [265.05–273.37] | -0.1% |

The isolated definite-clock Debug median was 7.6% slower, above the
advisory 5% target. The optimized median was 7.9% faster. The two Release
definite-clock ranges overlap because both builds had a slower fifth
trial. The wired ranges overlap in both configurations. These are
single-host, baseline-first runs and do not establish a minimum speedup
or a hard acceptance gate.

### Hotspots and attribution

- **Definite clock and output writes.** Native macOS `sample` collected
  roughly 3,000 steady-state main-thread samples per isolated workload.
  In Debug, stacks through the divider pin dictionary lookup and drive
  line accounted for 1,317/3,038 samples in the baseline and
  1,365/3,045 in the candidate. This is the largest clearly mapped
  common cost. The candidate also checks the clock symbol and optional
  second bucket and calls its reset/transition helper. In the definite
  fixture, each variant retained one scalar count. The
  samples do not apportion the 31 ms Debug median gap to individual
  scalar operations.
- **Provenance and identity.** The recovered candidate compares the
  last symbol and visible driver observations for X/Z. It has no
  separate sample-ordinal allocation path. On LOW/HIGH, the production
  net resolver returns before collecting driver observations, and the
  candidate skips observation dictionary comparison. In the isolated
  partial-clock workload each X is separated by LOW, so the symbol
  comparison short-circuits the dictionary equality and direct pin
  receives supply no driver observations. Same-symbol published samples,
  driver replacement and contentious nets are outside the timed fixtures.
- **Range and allocation work.** A separate instrumented isolated pass
  counted zero range merges, range buffer constructions, or range
  consensus scans in both definite variants and in the baseline
  partial-clock workload. Candidate partial clock entered 16,384
  unions, built 16,384 merge buffers and 252,928 range-advance buffers,
  materialized 2,048 singleton interval arrays, and scanned ranges for
  consensus 522,240 times across both buckets. It combined two buckets
  for consensus 16,384 times. Debug sampling found 436/2,986 candidate
  partial-clock samples under range transitions, 323/2,986 under
  output consensus and 20/2,986 under union. Array reserve and allocator
  frames appeared under range processing. Branch counts identify buffer
  construction sites. They are separate from heap allocation counts
  and from the uninstrumented wall times.
  Optimized partial clock still showed 491/3,069 samples under
  transitions and 48/3,069 under union. One steady-state range-advance
  stack alone contained 138 samples under Swift object allocation,
  with additional range buffer disposal and reference-counting frames.
  Optimized inlining limits output-consensus attribution.
- **Wired timebase.** Native samples attached to the actual workbench
  test process during the wired workload in both builds. Settling
  appeared in 2,451/2,547 baseline and 2,382/2,464 candidate Debug
  workload stacks, and in 472/504 and 530/563 Release stacks. Net
  resolution and timing configuration were prominent in Debug.
  CD4060 evaluation appeared in roughly 2–4% of wired workload
  stacks. Sampling and the overlapping timing ranges offer limited
  precision for the small wired median differences.

The isolated stacks came from a standalone native runner using the
recovered CD4060 and production Pin code with the same direct-pin clock
patterns. The wired stacks came from separate Xcode test invocations.
Sampling estimates inclusive activity and optimized frames may be
inlined. The full benchmark timings ran without sampling or counters.

### Ranked optimization proposals

1. Benchmark a definite-clock singleton path that handles known RESET
   and the previous binary level together before entering the two-bucket
   path. Keep power/startup invalidation, asynchronous reset, and X/Z
   observation identity intact. The Debug delta warrants this experiment.
   The optimized measurement provides little urgency for changing this path.
2. Cache each divider output pin and its precomputed bit mask at chip
   construction. Drive the same ten pins on every evaluation. This targets
   the largest common local cost in both builds while preserving output
   consensus and net settling.
3. Store a single contiguous count interval inline and advance it with
   scalar bounds, splitting explicitly at wrap. Merge scalar/inline
   intervals directly and retain sorted disjoint ranges for fragmented
   histories. Preserve the full-domain sentinel. This targets the
   observed range-advance allocations first and the smaller union cost
   second. Measure exact output-consensus caching only if scans remain
   expensive after the representation change.

Phase 5B.5a ends with profiling. The canonical CD4060 implementation and
all Phase 5B.4 files remain byte-identical to the starting snapshot.


## Phase 5B.5b.1 CD4060 output pin and bit-mask caching on 28 November 2026

The native arm64 WORK Mac runs used Xcode 27.2 (27B52) and isolated
snapshots of canonical HEAD `06bb45b8657a7b113e19732f74874bf67b5507fb`
with the local Phase 5B.1–5B.4 changes. The comparison source, migration
tests and timing fixture came from the original Phase 5B.5 gate workspace.
The source and timing fixture match the Phase 5B.5a recovery byte for byte.
The comparison CD4060 source SHA-256 is
`d9017692c9304edb0c234da97f4f84ab65e1158422fdb55d2b13a198aabcacc2`.

The only candidate source change creates a fixed list of the ten divider
output references and their bit masks during chip construction. Each list
entry holds the exact `Pin` instance installed at its physical number in
`pins`. Evaluation still makes all ten drive calls in the construction
iteration order and applies the same consensus expression. Clock history,
reset, power invalidation and startup code are byte-identical between
the two candidates.

### Native Debug correctness and regression

| Snapshot | Tests | Suites | Executions | Failures / skips |
| --- | ---: | ---: | ---: | ---: |
| Canonical Phase 5B.4 | 285 | 51 | 535 | 0 / 0 |
| Recovered candidate, focused CD4060 | 10 | 1 | 32 | 0 / 0 |
| Cached candidate, focused CD4060 | 10 | 1 | 32 | 0 / 0 |
| Recovered candidate, full regression | 289 | 51 | 553 | 0 / 0 |
| Cached candidate, full regression | 289 | 51 | 553 | 0 / 0 |

Xcode result identities for Phase 5B.4 match the preceding baseline
across all tests, suites and 347 parameterized executions. Both candidate
regressions retain all baseline identities and match one another,
including all 365 parameterized executions. The 18 added executions are
from `CD4060PowerTests.correlatedClock(automaticPower:unknown:)`,
`sameSymbolAndReset(automaticPower:unknown:)`,
`resolvedClock(automaticPower:)` and
`startupAndRestore(automaticPower:initial:)`. The focused suite also
passed `dividerRatios(automaticPower:)`, `candidateRollover()`,
`powerLoss(restoredClock:fault:)`, `uncertainReset(resetLevel:automaticPower:)`,
`resolvedReset(automaticPower:)` and `timebase()`. This covers all ten
physical divider outputs and 14-bit rollover, reset consensus, repeated
settling, explicit and automatic power, X/Z clock history, contention,
weak pulls and the deterministic 32,768 Hz to 1 Hz timebase. The existing
`uncertainReset` identity includes the recovered migration expectation
for a HIGH → X/Z → LOW bridge.


### Native arm64 matched benchmarks

Both variants ran the recovered Xcode fixture serially, with
`ENABLE_TESTABILITY=YES`, Debug `-Onone` and Release whole-module `-O`.
Each variant used one warm-up and five measured trials per workload, with
fixture creation and initial reset outside the timer. The unmodified
candidate ran first in Debug and the cached candidate ran first in Release.
Times are monotonic wall milliseconds, shown as median [minimum–maximum].
Negative changes indicate lower elapsed time.

The four direct-pin workloads each run 262,144 cycles and two evaluations
per cycle. The wired Explicit Power workload runs 65,536 half-period
events through Workbench in one virtual second and checks the CD4060 and
CD4027 endpoints. The harness assertions passed for both variants.

#### First pass

| Build | Workload | Unmodified (ms) | Cached (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 407.73 [405.05–416.34] | 429.01 [419.69–431.86] | +5.2% |
| Debug | partial-reset | 604.24 [598.90–608.26] | 628.49 [619.52–663.45] | +4.0% |
| Debug | partial-clock | 564.10 [554.34–569.06] | 571.13 [568.68–574.14] | +1.2% |
| Debug | unknown | 391.61 [390.74–393.63] | 398.34 [393.77–400.44] | +1.7% |
| Debug | wired | 1,776.01 [1,747.21–1,802.07] | 1,779.31 [1,754.87–1,822.35] | +0.2% |
| Release | definite | 68.97 [68.31–88.77] | 36.75 [36.66–37.23] | -46.7% |
| Release | partial-reset | 83.04 [81.92–83.76] | 48.74 [48.30–70.10] | -41.3% |
| Release | partial-clock | 84.26 [83.68–84.73] | 50.33 [49.95–51.24] | -40.3% |
| Release | unknown | 68.67 [67.84–68.68] | 36.77 [36.62–37.10] | -46.4% |
| Release | wired | 269.46 [268.94–271.91] | 281.24 [278.60–284.84] | +4.4% |

#### Reverse-order repeat

The repeat reused the built binaries, with the cached candidate first in
Debug and the unmodified candidate first in Release. Each run again used
one warm-up and five measured trials per workload.

| Build | Workload | Unmodified (ms) | Cached (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 400.08 [399.11–403.29] | 423.27 [404.32–427.93] | +5.8% |
| Debug | partial-reset | 583.52 [580.18–586.05] | 601.60 [595.72–603.49] | +3.1% |
| Debug | partial-clock | 531.72 [529.28–548.19] | 564.38 [554.86–575.39] | +6.1% |
| Debug | unknown | 381.98 [379.94–385.11] | 401.61 [399.96–405.51] | +5.1% |
| Debug | wired | 1,762.14 [1,740.23–1,772.85] | 1,760.98 [1,755.63–1,781.66] | -0.1% |
| Release | definite | 68.35 [67.50–83.53] | 35.85 [35.76–35.94] | -47.5% |
| Release | partial-reset | 80.82 [80.02–82.31] | 48.13 [47.10–62.36] | -40.4% |
| Release | partial-clock | 82.30 [81.98–82.88] | 48.95 [48.89–49.07] | -40.5% |
| Release | unknown | 67.33 [66.57–67.85] | 36.21 [35.94–36.63] | -46.2% |
| Release | wired | 273.85 [272.41–277.67] | 262.27 [260.56–264.40] | -4.2% |

### Retention decision and limits

Recommend retaining caching in the isolated Phase 5B.5 candidate for
review. All four isolated Release workloads were 40.3–47.5% faster by
median across the two passes, and their measured ranges were disjoint
within each comparison. The four isolated Debug medians were 1.2–6.1%
slower across the passes, including 5.2–5.8% for definite clock. Debug
wired medians stayed within 0.2% and the ranges overlapped. Release wired
changed from 4.4% slower to 4.2% faster when the order was reversed, so
the measurements do not establish a consistent wired benefit or
regression. Cached Release simulated 65,536 wired events in a median
262–281 ms per virtual second across the two passes.

These are single-host results from five timed trials per workload per
pass. The fixtures measure steady-state execution and exclude chip
construction. They do not quantify the cache's allocation cost or the
performance of the full six-digit clock. The Release result supports
retention for direct CD4060 evaluation with the measured Debug tradeoff.
Canonical production source remains at Phase 5B.4 pending review.


## Phase 5B.5b.2 CD4060 definite-clock singleton experiment on 28 November 2026

Used the native arm64 WORK Mac with Xcode 27.2 (27B52). The isolated
baseline is a byte-for-byte copy of the accepted Phase 5B.5b.1 cached
candidate. CD4060 source SHA-256 is
`684a396c1fb03739ac1bfcc13f7a995ce30210d9033be807fe97d19faa8ee0fb`.
The benchmark fixture has SHA-256
`95b13303d0cbead7ac29f6b8cea3ccda20472793033aa613adc0093f049c4f98`
in both trees. Canonical HEAD is
`06bb45b8657a7b113e19732f74874bf67b5507fb` with the local Phase 5B.4
production snapshot.

The isolated experiment adds a branch in `CD4060.evaluate()` gated on a
single count, a current binary clock, an initialized binary prior clock
and binary RESET. The prior clock is binary whenever a clock has been
sampled and the second bucket is absent. RESET HIGH sets the count to
zero asynchronously. RESET LOW advances only on HIGH to LOW, wrapping at
14 bits. The branch writes through the existing singleton and previous
clock fields and drives all ten cached pins using their cached masks.
The general path still handles startup, X/Z clocks and RESET, and
multi-count histories. It preserves correlated buckets, driver
observations and same-symbol publications. Power failure still clears the
count and clock history. The count range representation was unchanged.

The experiment extends the existing parameterized `correlatedClock`
test to traverse a second HIGH → X/Z → LOW bridge after seven definite
pulses, crossing the count-16 boundary with the expected exact count.
This exercises fast-path recovery and a second exit with accumulated
history in both power modes and for both uncertain symbols.

### Native arm64 Debug correctness

| Run | Tests | Suites | Executions | Failures / skips |
| --- | ---: | ---: | ---: | ---: |
| Exact cached baseline, full regression | 289 | 51 | 553 | 0 / 0 |
| Fast path, focused CD4060 suite | 10 | 1 | 32 | 0 / 0 |
| Fast path, full regression | 289 | 51 | 553 | 0 / 0 |

Both full runs match the accepted cached result in test and suite
identities, including all 365 parameterized argument identities. The
focused run matches all accepted focused identities. The full regressions
exclude the separately timed benchmark suite, as in Phase 5B.5b.1.

### Native arm64 matched benchmarks

Both versions used the same Xcode fixture with testability enabled, Debug
`-Onone` and Release whole-module `-O`. All workloads ran serially,
with one warmup and five measured trials per workload, per version and
order. Fixture construction and initial reset are outside the timer.
Each isolated workload runs 262,144 cycles and two evaluations per
cycle. The wired Explicit Power workload runs 65,536 clock events in
one simulated second through the Workbench CD4060 → CD4027 timebase.
Harness assertions passed in all runs. Times are monotonic wall
milliseconds as median [minimum–maximum]. Negative changes are faster.

#### First pass

Cached ran first in Debug. Fast path ran first in Release.

| Build | Workload | Cached baseline (ms) | Fast path (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 412.53 [407.91–422.51] | 419.69 [410.59–428.58] | +1.7% |
| Debug | partial-reset | 601.45 [598.78–603.70] | 616.52 [616.31–621.35] | +2.5% |
| Debug | partial-clock | 566.32 [560.15–570.64] | 578.31 [560.72–585.60] | +2.1% |
| Debug | unknown | 398.49 [392.52–400.81] | 416.83 [411.82–420.12] | +4.6% |
| Debug | wired | 1,767.23 [1,764.62–1,787.12] | 1,782.01 [1,767.73–1,808.83] | +0.8% |
| Release | definite | 36.29 [36.10–36.52] | 32.07 [31.67–32.89] | -11.6% |
| Release | partial-reset | 49.34 [48.70–62.85] | 51.07 [50.47–60.92] | +3.5% |
| Release | partial-clock | 50.18 [49.28–50.56] | 51.33 [50.06–51.92] | +2.3% |
| Release | unknown | 36.22 [35.86–36.57] | 38.66 [37.89–38.83] | +6.8% |
| Release | wired | 267.49 [264.32–268.69] | 267.27 [264.84–270.79] | -0.1% |

#### Reverse-order repeat

Fast path ran first in Debug. Cached ran first in Release. Both runs
reused the binaries from the first pass.

| Build | Workload | Cached baseline (ms) | Fast path (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 419.31 [415.32–421.62] | 418.65 [416.18–421.32] | -0.2% |
| Debug | partial-reset | 601.36 [592.86–625.30] | 615.47 [609.86–622.76] | +2.3% |
| Debug | partial-clock | 562.75 [556.28–593.02] | 579.86 [576.28–587.53] | +3.0% |
| Debug | unknown | 399.07 [397.76–404.80] | 401.42 [395.09–406.07] | +0.6% |
| Debug | wired | 1,773.28 [1,716.89–1,795.31] | 1,766.70 [1,742.30–1,772.43] | -0.4% |
| Release | definite | 36.70 [36.17–36.94] | 31.82 [31.55–31.93] | -13.3% |
| Release | partial-reset | 49.60 [47.75–50.12] | 50.09 [49.67–55.22] | +1.0% |
| Release | partial-clock | 50.25 [49.66–50.65] | 51.17 [51.00–51.38] | +1.8% |
| Release | unknown | 37.37 [36.79–37.66] | 38.70 [38.30–39.20] | +3.6% |
| Release | wired | 267.90 [255.17–269.45] | 260.40 [258.51–265.17] | -2.8% |

### Retention decision and limits

Discard the singleton branch and restore the isolated Phase 5B.5b.1
cached candidate. The Release definite-clock median fell by 11.6% and
13.3%, with disjoint trial ranges in both passes. That saved 4.2–4.9 ms
over 524,288 evaluations. Debug definite-clock medians changed by +1.7%
and −0.2%, with overlapping ranges. Release partial RESET, partial clock
and unknown count were slower in both orders. Unknown-count medians rose
by 6.8% and 3.6%, with disjoint ranges in both passes. Wired ranges
overlapped in all four comparisons. The wired median moved by +0.8% then
−0.4% in Debug and −0.1% then −2.8% in Release. The isolated Release
gain does not justify the extra branch and duplicated output loop given
the regressions outside definite-clock operation and the absence of a
clear wired gain.

The experiment changes and temporary test extension were removed from
the isolated source tree, which matched the accepted cached candidate
byte for byte after restoration. The experimental diff and native
result bundles remain in the phase workspace for inspection. Canonical
production source was verified byte for byte against Phase 5B.4.
Only this status entry was added to the canonical checkout.

These measurements cover one host, five timed trials per comparison and
steady-state fixtures. The timed direct-pin runs do not measure
same-symbol X/Z publication, contention, startup or power cycling.
Native correctness tests cover those paths. The benchmark excludes
construction and does not measure memory usage or the full six-digit
clock. Phase 5B.5b.2 ends here.


## Phase 5B.5b.3 CD4060 inline contiguous count intervals on 28 November 2026

Ran on the native arm64 WORK Mac with Xcode 27.2 (27B52). The
isolated baseline matched the accepted Phase 5B.5b.1 tree byte for byte.
Its CD4060 source SHA-256 was
`684a396c1fb03739ac1bfcc13f7a995ce30210d9033be807fe97d19faa8ee0fb`.
Both benchmark fixtures had SHA-256
`95b13303d0cbead7ac29f6b8cea3ccda20472793033aa613adc0093f049c4f98`.

Each correlated clock bucket can hold a scalar, an inline inclusive
interval, the full-domain sentinel, or sorted nonadjacent ranges backed
by an array. Contiguous advancement and union work directly on endpoints.
Advancing past 16,383 inserts zero and retains the shifted upper
fragment. The fallback merges sorted input ranges and defers allocating
an output buffer until it encounters a gap. Bit consensus uses the exact
ranges. Clock sampling, provenance, reset priority, and power
invalidation use the cached implementation's existing paths.

### Native arm64 Debug correctness

| Run | Tests | Suites | Executions | Failures / skips |
| --- | ---: | ---: | ---: | ---: |
| Accepted cached baseline, full regression | 289 | 51 | 553 | 0 / 0 |
| Inline interval, focused CD4060 suite | 12 | 1 | 37 | 0 / 0 |
| Inline interval, full regression | 291 | 51 | 558 | 0 / 0 |

The baseline reproduced every accepted test and suite identity and all
365 parameterized argument identities. The full candidate run preserved
them all and added two tests with five executions. The focused additions
compare unions, advancement, optional reset, canonical representations
and all 14 output bits against enumerated integer sets. The wired clock
test compares both clock buckets with an independent set model near
rollover in both power modes, including X/Z symbol changes, same-symbol
publication, control-only updates and reset. Existing tests cover the
power-loss lifecycle, contention and wired timebase.

### Native arm64 matched benchmarks

Used the unchanged five-workload fixture and the same testability,
Debug `-Onone` and Release whole-module `-O` settings for both
versions. Each workload ran one warmup and five timed trials per
version and order. The direct workloads use 524,288 evaluations.
The wired workload services 65,536 clock events through the explicit
power Workbench CD4060 → CD4027 timebase. Fixture construction and
initial reset are outside the timer. Times are median [minimum–maximum]
wall milliseconds. Negative changes are faster.

#### First pass

Cached ran first in Debug. Inline interval ran first in Release.

| Build | Workload | Cached baseline (ms) | Inline interval (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 421.98 [420.93–428.65] | 419.83 [416.08–425.23] | -0.5% |
| Debug | partial-reset | 610.04 [594.86–615.73] | 603.07 [598.85–606.78] | -1.1% |
| Debug | partial-clock | 571.56 [558.53–573.52] | 437.29 [434.92–438.84] | -23.5% |
| Debug | unknown | 400.28 [397.39–408.50] | 401.73 [396.32–406.23] | +0.4% |
| Debug | wired | 1,804.75 [1,784.20–1,827.16] | 1,740.65 [1,730.57–1,792.82] | -3.6% |
| Release | definite | 36.61 [36.47–36.91] | 36.84 [36.37–37.04] | +0.6% |
| Release | partial-reset | 48.01 [47.82–50.82] | 50.76 [49.63–63.13] | +5.7% |
| Release | partial-clock | 49.54 [49.09–49.84] | 41.96 [41.35–42.80] | -15.3% |
| Release | unknown | 36.63 [36.42–36.82] | 36.91 [36.73–37.15] | +0.8% |
| Release | wired | 274.30 [272.52–276.14] | 265.26 [264.34–268.17] | -3.3% |

#### Reverse-order repeat

Inline interval ran first in Debug. Cached ran first in Release. Both
runs reused the first-pass binaries.

| Build | Workload | Cached baseline (ms) | Inline interval (ms) | Median change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 457.98 [444.76–459.93] | 422.16 [419.71–425.56] | -7.8% |
| Debug | partial-reset | 642.14 [641.43–645.11] | 602.96 [595.77–624.34] | -6.1% |
| Debug | partial-clock | 577.90 [574.23–593.19] | 441.54 [436.77–448.59] | -23.6% |
| Debug | unknown | 424.91 [424.07–428.39] | 403.36 [401.86–406.46] | -5.1% |
| Debug | wired | 1,781.73 [1,769.17–1,796.84] | 1,765.13 [1,757.07–1,796.89] | -0.9% |
| Release | definite | 36.62 [36.05–36.76] | 36.61 [36.36–37.16] | -0.0% |
| Release | partial-reset | 48.75 [48.36–54.00] | 51.48 [50.46–63.86] | +5.6% |
| Release | partial-clock | 49.49 [49.42–50.07] | 41.74 [41.61–42.01] | -15.7% |
| Release | unknown | 36.52 [36.21–36.76] | 36.99 [36.66–37.35] | +1.3% |
| Release | wired | 260.28 [259.72–264.46] | 261.66 [258.68–262.03] | +0.5% |

### Range buffers and representation cost

An untimed replay of the direct-pin loops counted source-level requests
for nonempty range buffers at array literals and initial reservations.
The partial-clock workload went from 271,360 requests per trial to zero
(265 per 256-cycle block across 1,024 blocks). Partial reset stayed at
254,976 because its sets remain fragmented after the reset is released.
Definite clock and full-domain unknown stayed at zero. Both the required
bucket and its optional companion increased in stride from 16 to 24 bytes
each on arm64, adding 16 bytes across those two stored fields. These
counts describe range-buffer requests and field stride. Heap bytes,
allocator calls, and overall process memory were outside the measurement.

### Retention decision and limits

Retain the inline interval optimization in the isolated Phase 5B.5
candidate. Partial-clock medians improved by 23.5% and 23.6% in Debug
(134–136 ms saved per trial) and 15.3% and 15.7% in Release (7.6–7.8 ms
saved). The partial-clock trial ranges were disjoint in all four
comparisons. The range-buffer reduction and repeatable advantage in
both build modes justify the extra representation and merge logic.

Release partial reset was 5.6–5.7% slower, costing about 2.7 ms per
trial with overlapping ranges in both orders. The fragmented branch
still constructs buffers and incurs extra merge bookkeeping. The
Release unknown median rose 0.8–1.3%, with overlapping ranges. Release
definite clock was within 0.7%. Debug workloads other than partial
clock varied with the order, including a broad shift in the cached
medians on the repeat. Wired Debug medians improved 3.6% then 0.9%
with overlapping ranges. Wired Release moved from 3.3% faster to 0.5%
slower. The wired timings do not establish a repeatable benefit.

The timings cover steady-state fixtures on one host. Same-symbol X/Z
publication, contention, power cycling and startup are covered by
correctness tests. The full six-digit clock was outside the benchmark.
The candidate, focused tests, diff and native result bundles are in the
Phase 5B.5b.3 workspace. Canonical production files were verified byte
for byte against Phase 5B.4. This entry is the only canonical change.
Phase 5B.5b.3 ends here.


## Phase 5B.5c CD4060 final correctness and integration on 28 November 2026

Passed on the native arm64 WORK Mac with Xcode 27.2 (27B52) and
macOS 27.2.1. The retained Phase 5B.5b.3 tree was copied and compared byte
for byte. Its CD4060 SHA-256 is
`cacf5bc008b2d8581b9825607db9eabc475715960a57c5d90244576c50bd0983`.
The candidate uses cached pins and inline intervals. The discarded
singleton fast path is absent. The expanded verification copy adds
only `CD4060FinalVerificationTests.swift`. No correctness defects were
demonstrated and no candidate production changes were needed.

### Native arm64 Debug regression and Release application

| Run | Tests | Suites | Executions | Failures / skips |
| --- | ---: | ---: | ---: | ---: |
| Exact retained 5B.5b.3 candidate | 291 | 51 | 558 | 0 / 0 |
| Candidate with final verification tests | 293 | 52 | 562 | 0 / 0 |

The exact run matched the retained run in every suite, test and all
369 parameterized argument identities. The expanded run preserved all
baseline identities and added one suite, two tests and four executions.
Both runs excluded the separately timed benchmark suite, following
the retained baseline convention. The arm64 Release app built and
its executable was verified as Mach-O arm64.

### Exact counter-state verification

An independent oracle enumerated individual (count, prior clock)
states and verified both correlated buckets, consensus for all 14
internal bits, and the ten physical outputs. In Explicit and Automatic
Power it checked every rising and falling half-cycle of a complete
16,384-count rollover. Directed traces exercised fragmented intervals
across wrap, X and Z changes, same-symbol publications, control-only
updates, repeated settling, strong contention, masked weak
publications and weak-pull recovery, asynchronous RESET, startup and
power loss and restoration. A fixed-seed 512-step trace per power mode
combined all clock and RESET symbols. The retained test suite also
rechecked interval union and advancement against exact sets, RESET
weak pulls and contention, and startup/restoration at all four clock
symbols.

### Deterministic wired timebase

A wired Workbench Clock Source fed CD4060 pin 11 at 32,768 Hz.
CD4060 pin 3 fed CD4027 clock pin 3 and CD4027 Q fed CD4017 clock
pin 14. An injected time source and Workbench oscilloscope confirmed
every one of 163,840 input half-cycle edges per power mode over
2.5 simulated seconds, with timestamps equal to integer multiples
of 1/65,536 second. CD4060 Q14 changed at 0.25-second intervals
from 0.25 s through 2.50 s. CD4027 Q changed at 0.25, 0.75, 1.25,
1.75 and 2.25 s. CD4017 decoded counts 0 through 3, advancing on
the CD4027 rising edges at 0.25, 1.25 and 2.25 s. Both power modes
matched the same expected trace.

### Evidence and limits

The wired check measures ideal simulated time with an injected source
and a single downstream decade. Wall-clock scheduling accuracy,
physical oscillator behavior, and a full six-digit clock using this
candidate chain were outside the focused verification. The oracle
checks the directed and fixed-seed histories and the full definite
count domain. Possible uncertain histories are unbounded.
The first restricted Debug attempt could not start Xcode's Swift
macro plug-in service. The native rerun succeeded. The build's App
Intents metadata warning and test host's auto-shortcut service
messages had no test or build failures associated with them.

The candidate, test-only verification copy, commands, logs, native
Xcode result bundles and identity comparisons are retained in
`referenced-chatgpt-conversation-this-is-an-18/work` in the
28 November Codex workspace. The canonical checkout's 116 other
tracked and unignored files were verified byte for byte against
Phase 5B.4. The Phase 5B.5c status entry is the only canonical
change. Phase 5B.5c ends here.


## Phase 5B.5d CD4060 comparison and adoption gate on 28 November 2026

### Provenance and native Debug regression

Compared the exact canonical Phase 5B.4 implementation with the exact
Phase 5B.5c verification tree on the arm64 WORK Mac, macOS 27.2.1,
Xcode 27.2 (27B52). The canonical checkout was checked against the
Phase 5B.4 snapshot, including existing local changes. The candidate
has correlated clock histories, cached output pins and masks, and
inline contiguous intervals. Its verified production source excludes
the discarded singleton fast path.

- Phase 5B.4 CD4060 SHA-256:
  `0c62f09049a61105414d219783ad9ee3bf6346c9b47ca2db8bf9f122cfe03e04`
- Phase 5B.5c CD4060 SHA-256:
  `cacf5bc008b2d8581b9825607db9eabc475715960a57c5d90244576c50bd0983`

| Isolated tree | Tests | Suites | Executions | Failures / skips |
| --- | ---: | ---: | ---: | ---: |
| Canonical Phase 5B.4 | 285 | 51 | 535 | 0 / 0 |
| Exact Phase 5B.5c candidate | 293 | 52 | 562 | 0 / 0 |

Both runs matched their historical test, suite and parameterized
argument identities exactly. The candidate preserved all canonical
identities. The timing harness was excluded from regression counts.

### Benchmark method

Used one byte-identical benchmark in both isolated trees, with Debug
and Release testability enabled and native arm64 execution. The
original five-workload fixture was reused with an exact serviced-time
assertion outside the timed region. Each workload ran one warmup
followed by five measured trials per binary in each pass. Builds were
reused on the reverse pass, with runs serialized. First-pass Debug was
canonical then candidate, and Release was candidate then canonical.
Both orders were reversed for the repeat. Changes compare median
candidate wall time with canonical wall time. Negative is faster.

The four isolated workloads each ran 262,144 cycles with direct CD4060
pin drives and checked the final Q14. The wired workload used the
explicit-power Workbench path, driving CD4060 into CD4027 from a
32,768 Hz Clock Source. It checked stable, advancing service to exactly
1 simulated second (65,536 half-cycle events) and both final outputs.
Both Debug regressions also checked output transitions immediately
before and at the same expected simulated times through 2.25 s. The
candidate additionally passed the Phase 5B.5c edge-by-edge timebase
verification in both power modes.
### First order

| Build | Workload | Phase 5B.4 median [range], ms | Phase 5B.5c median [range], ms | Change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 418.70 [414.77–419.84] | 422.68 [407.58–426.37] | +0.9% |
| Debug | partial-reset | 593.21 [589.51–598.70] | 586.82 [583.97–588.40] | -1.1% |
| Debug | partial-clock | 418.24 [415.02–420.24] | 439.18 [428.70–441.66] | +5.0% |
| Debug | unknown | 387.73 [381.74–396.28] | 398.90 [395.96–400.51] | +2.9% |
| Debug | wired | 1,746.77 [1,734.88–1,784.89] | 1,749.93 [1,724.38–1,756.64] | +0.2% |
| Release | definite | 69.42 [68.51–70.15] | 36.28 [35.92–36.36] | -47.7% |
| Release | partial-reset | 82.19 [81.82–82.57] | 50.20 [49.25–65.48] | -38.9% |
| Release | partial-clock | 76.47 [75.58–77.13] | 41.47 [40.95–41.76] | -45.8% |
| Release | unknown | 72.01 [71.80–72.17] | 37.30 [36.28–37.63] | -48.2% |
| Release | wired | 267.63 [265.63–268.57] | 263.96 [261.83–264.62] | -1.4% |

### Reverse order

| Build | Workload | Phase 5B.4 median [range], ms | Phase 5B.5c median [range], ms | Change |
| --- | --- | ---: | ---: | ---: |
| Debug | definite | 412.59 [409.94–417.55] | 416.79 [411.42–420.47] | +1.0% |
| Debug | partial-reset | 597.07 [592.94–600.61] | 592.27 [588.77–600.61] | -0.8% |
| Debug | partial-clock | 413.79 [411.73–415.35] | 438.99 [432.85–440.07] | +6.1% |
| Debug | unknown | 394.64 [390.71–413.90] | 399.60 [396.98–416.05] | +1.3% |
| Debug | wired | 1,770.77 [1,756.91–1,789.34] | 1,769.35 [1,740.20–1,783.50] | -0.1% |
| Release | definite | 70.96 [70.40–79.86] | 36.18 [35.77–36.47] | -49.0% |
| Release | partial-reset | 81.84 [81.61–82.79] | 50.72 [49.87–65.93] | -38.0% |
| Release | partial-clock | 73.30 [73.08–73.79] | 41.42 [41.17–42.03] | -43.5% |
| Release | unknown | 69.10 [68.74–70.52] | 36.50 [36.43–36.68] | -47.2% |
| Release | wired | 264.71 [262.65–264.84] | 264.28 [262.09–266.57] | -0.2% |

### Decision, tradeoffs and limits

Adopt the exact verified candidate. The four isolated Release cases
improved in both orders with disjoint trial ranges. Definite improved
47.7–49.0%, partial RESET 38.0–38.9%, partial clock 43.5–45.8%, and
full unknown 47.2–48.2%. The fragmented partial-RESET candidate had
an upper-tail trial near 66 ms in each order, still below the fastest
canonical trial. Wired Release improved 1.4% then 0.2% (3.67 ms and
0.43 ms), and the repeat's ranges overlapped. Wired Debug changed
+0.2% then −0.1%, with overlapping ranges. These are small wired
differences, with no material repeatable regression or established
practical wired speedup.

Debug partial clock was repeatably 5.0–6.1% slower (21–25 ms per
262,144 cycles), with disjoint ranges in both orders. Debug definite
rose 0.9–1.0%, full unknown rose 1.3–2.9%, and partial RESET fell
0.8–1.1%. Accept the isolated Debug costs given the verified
four-state behavior, large Release improvements and stable wired
results. The earlier inline-interval comparison measured 16 extra bytes
across two stored bucket fields and fewer requests for nonempty
range buffers on its partial-clock fixture. Whole-process memory and
allocation counts were outside this comparison.

These are short, fixed fixtures on one host. The wired run measures
Workbench service of ideal simulated time for one divider and one
flip-flop. Physical oscillator timing, UI scheduling at real-time
rates and full six-digit clock performance remain unverified.

### Canonical adoption and git status

Copied the verified `SimulationCore/Components/CD4060.swift`,
`CMOS4000SimulatorTests/CD4060PowerTests.swift` and
`CMOS4000SimulatorTests/CD4060FinalVerificationTests.swift` byte for
byte. Verified the remaining canonical source and project files
against the pre-adoption snapshot. The benchmark harness stayed in
the isolated trees. The full native arm64 Debug suite passed all 293
test identities, 52 suites and 562 executions with zero failures or
skips, matching the verified candidate including parameterized
arguments. The standard Release app built with the project's normal
Release settings and an arm64 destination. Its executable is Mach-O
arm64.

Git remains on `main...origin/main` at
`06bb45b8657a7b113e19732f74874bf67b5507fb`, with local changes and
nothing staged. Relative to the starting worktree, the source and
power test are modified and the final verification test is untracked.
This entry extends the already modified `PROJECT_STATUS.md`.
The ten previously modified paths and two previously untracked paths
remain present. `git diff --check` passed.

Native result bundles, raw benchmark trials, identity lists, build
logs and source checks are in the 28 November Codex workspace under
`referenced-chatgpt-conversation-this-is-an-19/work`.
Phase 5B.5d ends here.
