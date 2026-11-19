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

### Counters

| Component | Description |
|---|---|
| CD4017 | Decade counter with decoded outputs |
| CD4026 | Decade counter with 7-segment outputs |
| CD4516 | Binary up/down counter |
| CD4518 | Dual BCD counter |
| CD4520 | Dual binary counter |

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

## Project maintenance

Update this document when new components are implemented and tested.

Keep the component inventory accurate and distinguish completed functionality from planned development.

The simulator should remain useful as both an educational tool and a practical circuit-design workbench.