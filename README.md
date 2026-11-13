# How to set up TwinCAT-HMI-CNC:

Make sure you have Visual Studio 2022/2026 or TwinCAT XAE installed.  
Make sure you have TwinCAT TcPkg installed and correctly configured. (Feed, Integration, etc.)  
Make sure you have the necessary licenses for TwinCAT HMI and any other required TwinCAT components. (Or create a 7-Day trial license if needed)

A PLC-example is included in the repository under the "CNC Project 4 Axis and Spindle" folder.

### Required Licenses: (For this project in particular)
- TF5310 - TC3 CNC HMI Base


### Step-By-Step Repo Setup:

1. Download this repository and place it in your desired engineering project folder location.

2. Run `TwinCAT-HMI-CNC\downloadPackages.ps1` to download the required TcPkg packages.
      - This script will install the required TcPkg packages for the TwinCAT HMI CNC project.
      - First it will install the TcHMI Engineering Workload and ask to update if newer versions are available.
      - Then it will proceed to install any additional required TcPkg packages for the TwinCAT HMI CNC project.
      - In File Explorer, right-click the actual `TwinCAT-HMI-CNC\downloadPackages.ps1` and select **Copy as path**.
      - In a PowerShell window, run `Unblock-File -LiteralPath "C:\path\to\downloadPackages.ps1"`, replacing the example path, including its quotes, with the copied quoted path. Only unblock scripts you trust.
      - In the same PowerShell window, run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`. This setting lasts only until the window closes; administrator privileges are not required to set it.
      - Launch the script with `& "C:\path\to\downloadPackages.ps1"`, replacing the example path with the same copied quoted path. 
      - Follow any prompts that appear during the script execution to complete the installation of the required TcPkg packages.

3. Open the TwinCAT HMI CNC project in Visual Studio or TwinCAT XAE.
      - Navigate to the project folder where you placed this repository.
      - Open the solution file (*.sln) to load the project.
      - Ensure that all required TcPkg packages are correctly installed and referenced in the project.

4. Use the TwinCAT HMI CNC project like you would with any other TwinCAT HMI project.
      - LiveView, Publish, User-/Permission management, and other standard TwinCAT HMI functionalities.

### Refer to the TwinCAT HMI/CNC documentation for detailed guidance on using specific features and functionalities within the project.
