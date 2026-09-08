# TF5310 Samples

## Introduction

This repository currently contains two sample projects:

- **TF5310_HmiProject** – a template HMI project for TE2000 (TwinCAT HMI), showcasing a CNC-oriented user interface.
- **CNC Project 4 Axis and Spindle** – a sample TwinCAT PLC project implementing a 4-axis CNC channel with spindle control.

## Getting Started

### HMI Project Dependencies

The HMI project (`TF5310_HmiProject`) depends on a number of Beckhoff TwinCAT HMI packages. These packages are not included in the repository and must be installed via the Beckhoff Package Manager before the project can be opened and built:

| Package ID | Version |
| --- | --- |
| Beckhoff.TwinCAT.HMI.Analytics.Controls | 1.36.63 |
| Beckhoff.TwinCAT.HMI.Analytics.ControlsExtension | 1.36.63 |
| Beckhoff.TwinCAT.HMI.BaseTemplate | 14.4.4 |
| Beckhoff.TwinCAT.HMI.CNC.Base | 0.0.122 |
| Beckhoff.TwinCAT.HMI.CNC.Server | 0.2.3 |
| Beckhoff.TwinCAT.HMI.Controls | 14.6.20 |
| Beckhoff.TwinCAT.HMI.EcDiagnostics | 23.0.198 |
| Beckhoff.TwinCAT.HMI.EcDiagnosticsControl | 14.4.3 |
| Beckhoff.TwinCAT.HMI.EventLogger | 23.0.421 |
| Beckhoff.TwinCAT.HMI.Framework | 14.4.42 |
| Beckhoff.TwinCAT.HMI.Functions | 14.4.3 |
| Beckhoff.TwinCAT.HMI.Mdp | 23.0.198 |
| Beckhoff.TwinCAT.HMI.PDFViewer | 14.4.4 |

All packages target the `native1.12-tchmi` framework. Install them through the TwinCAT HMI Package Manager (or restore them via `packages.config`) before opening the solution in Visual Studio/TwinCAT Engineering.

## Build and Test

### CNC PLC Project

1. Open `CNC Project 4 Axis and Spindle/CNC Demo.tsproj` in TwinCAT XAE (Visual Studio with the TwinCAT extension installed).
2. Make sure the `TC3_CNCPLCBase` PLC project resolves its library references (see `_Libraries`); install any missing libraries through the TwinCAT Library Repository if needed.
3. Build the PLC project and activate the configuration on a local or remote TwinCAT runtime to test the CNC channel and axis/spindle behavior.

### HMI Project

1. Install the Beckhoff HMI packages listed above via the Package Manager.
2. Open `TF5310_HmiProject/TwinCAT-HMI-CNC.sln` in Visual Studio.
3. Build the solution; TwinCAT HMI will restore any remaining NuGet-style package references automatically.
4. Run/deploy the HMI project (e.g. via the built-in HMI server) and connect it to the CNC PLC project to test the full application end to end.



