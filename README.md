# TF5310 Samples (V1.0.0)

## Introduction

This repository currently contains two sample projects:

- **TF5310_HmiProject** – a template HMI project for TE2000 (TwinCAT HMI), showcasing a CNC-oriented user interface.
- **CNC Project 4 Axis and Spindle** – a sample TwinCAT PLC project implementing a 4-axis CNC channel with spindle control.

## Getting Started

## Build and Test

The HMI project is the primary sample in this repository. The CNC PLC project is required alongside it, since it contains all the necessary CNC configuration and settings that the HMI connects to.

### HMI Project

### How to set up TwinCAT-HMI-CNC:

Make sure you have Visual Studio 2022/2026 or TwinCAT XAE installed.  
Make sure you have TwinCAT TcPkg installed and correctly configured. (Feed, Integration, etc.)  
Make sure you have the necessary licenses for TwinCAT HMI and any other required TwinCAT components. (Or create a 7-Day trial license if needed)

A PLC-example is included in the repository under the "CNC Project 4 Axis and Spindle" folder.

### Required Licenses: (For this project in particular)
- TF5310 - TC3 CNC HMI Base


### Step-By-Step Repo Setup:

1. Download this repository and place it in your desired engineering project folder location.

2. Run ".\TF5310_HmiProject\TwinCAT-HMI-CNC\downloadPackages.ps1" to download the required TcPkg packages.
      - This script will install the required TcPkg packages for the TwinCAT HMI CNC project.
      - First it will install the TcHMI Engineering Workload and ask to update if newer versions are available.
      - Then it will proceed to install any additional required TcPkg packages for the TwinCAT HMI CNC project.
      - Make sure you have PowerShell execution policy set to allow running scripts. You can set it by running `Set-ExecutionPolicy RemoteSigned` in an elevated PowerShell window, before executing the downloadPackages.ps1 script.

3. Open the TwinCAT HMI CNC project in Visual Studio or TwinCAT XAE.
      - Navigate to the project folder where you placed this repository.
      - Open the solution file (*.sln) to load the project.
      - Ensure that all required TcPkg packages are correctly installed and referenced in the project.

4. Use the TwinCAT HMI CNC project like you would with any other TwinCAT HMI project.
      - LiveView, Publish, User-/Permission management, and other standard TwinCAT HMI functionalities.

##### Refer to the TwinCAT HMI/CNC documentation for detailed guidance on using specific features and functionalities within the project.


### CNC PLC Project

1. Open `CNC Project 4 Axis and Spindle/CNC Demo.tsproj` in TwinCAT XAE (Visual Studio with the TwinCAT extension installed).
2. Make sure the `TC3_CNCPLCBase` PLC project resolves its library references (see `_Libraries`); install any missing libraries through the TwinCAT Library Repository if needed.
3. Build and activate the PLC project on a local or remote TwinCAT runtime. It provides all the CNC settings and configuration required by the HMI project, so it must be running for the HMI to work correctly.



