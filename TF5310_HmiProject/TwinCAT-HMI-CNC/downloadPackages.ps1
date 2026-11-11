param(
	[string]$PackagesConfigPath = (Join-Path $PSScriptRoot 'packages.config')
)

$ErrorActionPreference = 'Stop'

try {
$packageMapping = @{
	'Beckhoff.TwinCAT.HMI.Analytics.ControlsExtension' = 'TwinCAT.HMI.AnalyticsControls'
	'Beckhoff.TwinCAT.HMI.Analytics.Framework' = 'TwinCAT.HMI.AnalyticsControls'
	'Beckhoff.TwinCAT.HMI.Analytics.Interactive' = 'TwinCAT.HMI.AnalyticsControls'
	'Beckhoff.TwinCAT.HMI.BaseTemplate' = 'TwinCAT.HMI.BaseTemplate'
	'Beckhoff.TwinCAT.HMI.CNC.Base' = 'TwinCAT.HMI.CNC.Base'
	'Beckhoff.TwinCAT.HMI.CNC.Server' = 'TwinCAT.HMI.CNC.Server'
	'Beckhoff.TwinCAT.HMI.Controls' = 'TwinCAT.HMI.Controls'
	'Beckhoff.TwinCAT.HMI.EcDiagnostics' = 'TwinCAT.HMI.EcDiagnostics'
	'Beckhoff.TwinCAT.HMI.EcDiagnosticsControl' = 'TwinCAT.HMI.EcDiagnosticsControl'
	'Beckhoff.TwinCAT.HMI.EventLogger' = 'TwinCAT.HMI.EventLogger'
	'Beckhoff.TwinCAT.HMI.Framework' = 'TwinCAT.HMI.Framework'
	'Beckhoff.TwinCAT.HMI.Functions' = 'TwinCAT.HMI.Functions'
	'Beckhoff.TwinCAT.HMI.Mdp' = 'TwinCAT.HMI.Mdp'
	'Beckhoff.TwinCAT.HMI.PDFViewer' = 'TwinCAT.HMI.PDFViewer'
	'Beckhoff.TwinCAT.HMI.ResponsiveNavigation' = 'TwinCAT.HMI.ResponsiveNavigation'
	'Beckhoff.TwinCAT.HMI.Server.Engineering' = 'TwinCAT.HMI.Server.Engineering'
	'Microsoft.TypeScript.MSBuild' = 'TypeScript.Beckhoff'
}

[xml]$packagesConfig = Get-Content -LiteralPath $PackagesConfigPath -Raw
$packages = $packagesConfig.SelectNodes('/packages/package')
if ($packages.Count -eq 0) {
	throw "No packages found in $PackagesConfigPath"
}

$packageVersions = @{}
$installVersions = [ordered]@{}
foreach ($package in $packages) {
	$packageId = $package.GetAttribute('id')
	if ([string]::IsNullOrWhiteSpace($packageId)) {
		throw "Package without an id in $PackagesConfigPath"
	}
	if ($packageVersions.ContainsKey($packageId)) {
		throw "Duplicate package: $packageId"
	}
	if (-not $packageMapping.ContainsKey($packageId)) {
		throw "No tcpkg mapping defined for package: $packageId"
	}

	$packageVersion = $package.GetAttribute('version')
	$packageVersions[$packageId] = $packageVersion
	$tcpkgName = $packageMapping[$packageId]
	if ($installVersions.Contains($tcpkgName) -and $installVersions[$tcpkgName] -cne $packageVersion) {
		throw "Packages mapped to $tcpkgName request different versions: $($installVersions[$tcpkgName]) and $packageVersion"
	}
	$installVersions[$tcpkgName] = $packageVersion
}

foreach ($tcpkgName in $installVersions.Keys) {
	$packageVersion = $installVersions[$tcpkgName]
	if ($packageVersion -notmatch '\A[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z') {
		throw "Expected an exact package version for ${tcpkgName}: '$packageVersion'"
	}
}

$installFailures = [System.Collections.Generic.List[string]]::new()
$workloadName = 'TE2000.HMIEngineering.XAE'
Write-Host "Checking latest version of $workloadName"
try {
	$installedWorkloadJson = & tcpkg list --installed --exact $workloadName --as-json
	if ($LASTEXITCODE -ne 0) {
		throw "tcpkg list failed (exit $LASTEXITCODE)"
	}

	$installedWorkload = @(($installedWorkloadJson | ConvertFrom-Json -ErrorAction Stop) |
		Where-Object { $_.Id -eq $workloadName })
	$workloadAction = $null
	if ($installedWorkload.Count -gt 0) {
		$outdatedWorkloadJson = & tcpkg list --outdated --exact $workloadName --as-json
		if ($LASTEXITCODE -ne 0) {
			throw "tcpkg list --outdated failed (exit $LASTEXITCODE)"
		}

		$outdatedWorkload = @(($outdatedWorkloadJson | ConvertFrom-Json -ErrorAction Stop) |
			Where-Object { $_.Id -eq $workloadName })
		if ($outdatedWorkload.Count -gt 0) {
			$updateWorkload = Read-Host "A newer $workloadName version is available. Update it? [y/n]"
			if ($updateWorkload -match '\A(?i:y|yes)\z') {
				Write-Host "Updating $workloadName to the latest version"
				& tcpkg upgrade -y $workloadName
				$workloadAction = 'upgrade'
			}
			else {
				Write-Host "Keeping the installed $workloadName version"
			}
		}
		else {
			Write-Host "$workloadName is already up to date"
		}
	}
	else {
		Write-Host "Installing $workloadName at the latest version"
		& tcpkg install -y $workloadName
		$workloadAction = 'install'
	}

	if ($workloadAction -and $LASTEXITCODE -ne 0) {
		$installFailures.Add("tcpkg $workloadAction failed for $workloadName (exit $LASTEXITCODE).")
	}
}
catch {
	$installFailures.Add("Could not install or update ${workloadName}: $($_.Exception.Message)")
}

Write-Host
$isFirstInstall = $true
foreach ($tcpkgName in $installVersions.Keys) {
	$packageVersion = $installVersions[$tcpkgName]
	if (-not $isFirstInstall) {
		Write-Host
	}
	$isFirstInstall = $false
	Write-Host "Installing $tcpkgName=$packageVersion"
	try {
		& tcpkg install -y "$tcpkgName=$packageVersion"
	}
	catch {
		$installFailures.Add("tcpkg install could not run for ${tcpkgName}=${packageVersion}: $($_.Exception.Message)")
		continue
	}
	if ($LASTEXITCODE -ne 0) {
		$installFailures.Add("tcpkg install failed for $tcpkgName=$packageVersion (exit $LASTEXITCODE). Check configured tcpkg sources and package availability.")
	}
}

if ($installFailures.Count -gt 0) {
	throw "One or more tcpkg installs failed:`n- $($installFailures -join "`n- ")"
}
}
catch {
	Write-Host
	Write-Host "Package download failed: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host
	Read-Host 'Press Enter to close'
	throw
}

Write-Host
Read-Host 'Package download completed. Press Enter to close'
