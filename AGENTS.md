# AGENTS.md — CMOS Hardware Simulator

## Project location

The canonical project directory is:

`/Users/mark.adams/Documents/GitHub/CMOS_Hardware_Simulator`

This is a macOS SwiftUI application developed using Xcode.

Do not modify the previous CMOS4000Simulator project location.

## Project purpose

Develop an interactive hardware simulator for CMOS digital logic circuits, initially focusing on the CD4000 series.

The simulator supports individual IC pin connections, interactive wiring, digital logic simulation and visual circuit behaviour.

## Development guidelines

- Preserve existing working functionality when adding components.
- Reuse existing component models, rendering and simulation infrastructure where practical.
- Keep electrical simulation logic separate from visual presentation.
- Use actual IC pin numbers and datasheet-verified behaviour.
- Model power connections, control inputs and logic polarity correctly.
- Preserve existing wiring and workspace functionality.
- Follow the project's established SwiftUI and naming conventions.
- Avoid unnecessary changes to unrelated files.
- Build and test changes before reporting completion.
- Do not commit or push changes unless requested.

## Component inventory

The following components have been implemented and tested.

### Logic gates

| Component | Description |
|---|---|
| CD4011 | Quad two-input NAND gate |
| CD4071 | Quad two-input OR gate |
| CD4081 | Quad two-input AND gate |
| CD40106 | Hex digital Schmitt-symbol inverter |

CD4011/CD4071/CD4081 use separately placed A–D gates and one shared E power unit. Preserve physical pin mapping (1/2→3, 5/6→4, 8/9→10, 12/13→11), VDD on 14, and VSS on 7. All units share one underlying chip instance.

For CD4071, any HIGH input establishes HIGH. Two LOW inputs establish LOW. Other combinations produce X, including LOW with an unknown or disconnected input. Preserve the shared unpowered-output X policy and Automatic Power behaviour.

### Timers

| Component | Description |
|---|---|
| NE555 | Digital latch plus ideal RC timing for standard astable/monostable circuits |

NE555 uses pins 1 GND, 2 TRIG, 3 OUT, 4 active-LOW RESET, 5 CONT, 6 THRES, 7 DISCH, 8 VCC. RESET overrides the comparators; LOW TRIG sets OUT even with HIGH THRES. HIGH TRIG/HIGH THRES resets it; HIGH TRIG/LOW THRES holds its state. DISCH sinks LOW when OUT is LOW and is HIGH-Z when OUT is HIGH. Preserve shared power validation and latch invalidation on supply loss.

`NE555TimingSystem` recognises standard grounded-capacitor astable (two resistors) and monostable (one resistor) networks using actual nets and component values. It integrates ideal exponential charge/discharge, feeds 1/3 and 2/3 supply comparator inputs to NE555, and settles every output edge. Preserve the longer startup pulse (ln(3), versus steady-state ln(2)), held-trigger priority, and bounded elapsed-time catch-up alongside external clocks. Shared power validation remains in SimulationEngine.

This is a limited ideal 5 V RC model, not a general analog solver. Reject unsupported timing loads/networks and reversed polarized timing capacitors with a warning and X. Require actual +5 V/GND timing rails even in Automatic Power mode. CONT may be open or capacitor-bypassed to GND; driven control voltages remain unsupported. Rewiring/reopen/power restoration restarts timing-capacitor voltage at zero; value edits retain its current voltage. A monostable needs a valid reset/trigger to establish known state. Consult PROJECT_STATUS.md for wiring and test values.

### Capacitors

| Component | Description |
|---|---|
| C_Polarized | Editable µF; pin 1 positive, pin 2 negative; default 10 µF |
| C_Small | Editable nF; non-polarized; default 100 nF |

Preserve the KiCad capacitor plate styling: C_Polarized has an outlined positive plate and a filled negative plate, with the positive-side + marker. Import the plate fill metadata rather than guessing polarity from placement or rotation.

Preserve right-click Set Capacitance text editors, positive finite-value validation, labels, rotation, Undo/Redo and save/open. Outside recognised NE555 timing networks these are DC-open elements. Timing resistors must stop their legacy weak digital drive; ordinary resistors keep their existing digital behaviour. Do not silently extend the RC model to arbitrary circuits.

### Counters

| Component | Description |
|---|---|
| CD4017 | Decade counter with decoded outputs |
| CD4026 | Decade counter with 7-segment outputs |
| CD4060 | External-clock binary divider |
| CD4510 | Presettable BCD up/down counter with carry |
| CD4516 | Binary up/down counter |
| CD4518 | Dual BCD counter |
| CD4520 | Dual binary counter |

### Bidirectional switches

| Component | Description |
|---|---|
| CD4051 | One 8-channel switch |
| CD4052 | Two 4-channel switches with shared A/B selectors |
| CD4053 | Three 2-channel switches with independent A/B/C selectors |

These packages model closed channels as bidirectional digital net connections. Preserve driver strength, contention, and high impedance across connected nets. In Explicit Power mode wire VDD to +5 V and both VSS and VEE to GND. INH must be LOW to enable routing.

### BCD-to-7-segment decoders

| Component | Description |
|---|---|
| CD4511 | BCD-to-7-segment latch/decoder/driver |
| CD4543 | BCD-to-7-segment latch/decoder/driver |

Preserve the implemented control-pin behaviour, including latch, blanking, lamp-test and phase functions where applicable.

### Seven-segment displays

| Component | Type | Segment activation |
|---|---|---|
| MAN74A | Common cathode | Active HIGH |
| MAN72A | Common anode | Active LOW |

Both displays have been implemented and tested.

Preserve individual wiring of segments A–G and decimal point.

The MAN74A requires its common-cathode pins 4 and 12 connected to GND. The MAN72A requires its common-anode pins connected to VCC according to its verified pinout.

Display segments must respond to their electrical connections, not automatically interpret BCD values.

## Workbench files and controls

- Preserve File → Open… (⌘O) and File → Save… (⌘S). Commands use the focused Workbench window.
- Keep labelled Open and Save buttons accessible when the controls wrap in narrower windows.
- Save circuits as JSON. Open also accepts legacy Workbench files with other filename extensions.
- Validate archive contents before replacing the current circuit, and report file errors to the user.
- Preserve saved package identities, shared components, wiring, junctions, positions, rotations, component settings, and power mode.
- Manual Clock Source components reopen paused; valid powered NE555 RC circuits start automatically. Archives preserve circuit configuration, not running sequential state or capacitor charge.
- For file-workflow changes, verify the native Save/Open dialogs as well as archive round-trip tests.

## Testing requirements

For all new or modified components, verify:

- Physical pin numbering and pin mapping.
- Power and common-connection behaviour.
- HIGH, LOW and disconnected input behaviour.
- Clock-edge and reset behaviour where applicable.
- Control-pin truth tables.
- Integration with existing components.
- No regressions in previously tested functionality.

## Development priorities

1. Maintain a stable and accurate digital simulation engine.
2. Expand the CMOS component library using verified datasheets.
3. Improve wiring, circuit editing and debugging.
4. Support increasingly complex circuits built from multiple interconnected components.
5. Work toward simulating a complete CMOS digital clock.

## Latest verification

On 20 November 2026, the capacitor/NE555 RC implementation passed all 84 test case executions. Coverage includes capacitor validation/DC isolation/symbols, Undo/Redo, archives, exponential charging, astable startup/steady-state timing, monostable reset/timeout/held trigger, R/C scaling, downstream edge counting, bounded scheduling, power cycling, polarity rejection, unsupported wiring, and Workbench automatic restart after reopen. The initial downstream-count test had an incorrect expected interval; this was corrected. Mixed-clock regression tests use an injected elapsed-time source to avoid mixing wall time with virtual time. No failing tests remain. Xcode emitted only the App Intents metadata extraction warning (no AppIntents dependency).

Native UI checks confirmed both capacitor symbols and text-field units, changed values to 47 µF and 22 nF, rejected zero, and saved/cleared/reopened those values through the native dialogs.

The subsequent capacitor negative-plate rendering correction also passed the full macOS Xcode suite.

The previous Save/Open fix passed the full suite and native save/clear/reopen checks. Preserve those file controls.

## Project maintenance

Update this document when new components are implemented and tested.

Keep the component inventory accurate and distinguish completed functionality from planned development.

The simulator should remain useful as both an educational tool and a practical circuit-design workbench.
