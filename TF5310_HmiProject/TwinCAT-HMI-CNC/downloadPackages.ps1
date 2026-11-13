param(
	[string]$PackagesConfigPath = (Join-Path $PSScriptRoot 'packages.config')
)

$ErrorActionPreference = 'Stop'

Write-Host 'Starting package installation...'
Write-Host

function Read-YesNo {
	param([string]$Prompt)

	do {
		$answer = Read-Host $Prompt
		if ($null -eq $answer) {
			throw 'Input ended before a yes/no answer was provided.'
		}
		$answer = $answer.Trim()
		if ($answer -notmatch '\A(?i:y|yes|n|no)\z') {
			Write-Host 'Please enter y or n.'
		}
	} while ($answer -notmatch '\A(?i:y|yes|n|no)\z')

	return $answer -match '\A(?i:y|yes)\z'
}

function Get-InstalledTcpkgPackage {
	param([string]$PackageName)

	$installedPackagesJson = & tcpkg list --installed --all --include-prereleases --exact $PackageName --as-json
	if ($LASTEXITCODE -ne 0) {
		throw "tcpkg list failed for $PackageName (exit $LASTEXITCODE)."
	}

	($installedPackagesJson | ConvertFrom-Json -ErrorAction Stop) |
		Where-Object { $_.Id -eq $PackageName }
}

function Test-InstalledTcpkgPackage {
	param(
		[string]$PackageName,
		[string]$PackageVersion
	)

	$matchingPackages = @(Get-InstalledTcpkgPackage -PackageName $PackageName |
		Where-Object { $_.Version -eq $PackageVersion })
	return $matchingPackages.Count -gt 0
}

function Compare-TcpkgVersion {
	param([string]$Left, [string]$Right)

	$pattern = '\A(?<Core>[0-9]+(?:\.[0-9]+){1,3})(?:-(?<Pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z'
	if ($Left -notmatch $pattern) { throw "Invalid installed package version: '$Left'" }
	$leftCore = $Matches.Core.Split('.')
	$leftPre = $Matches.Pre
	if ($Right -notmatch $pattern) { throw "Invalid requested package version: '$Right'" }
	$rightCore = $Matches.Core.Split('.')
	$rightPre = $Matches.Pre

	for ($i = 0; $i -lt 4; $i++) {
		$leftNumber = if ($i -lt $leftCore.Count) { [decimal]$leftCore[$i] } else { 0 }
		$rightNumber = if ($i -lt $rightCore.Count) { [decimal]$rightCore[$i] } else { 0 }
		if ($leftNumber -ne $rightNumber) { return $leftNumber.CompareTo([decimal]$rightNumber) }
	}
	if (-not $leftPre -and -not $rightPre) { return 0 }
	if (-not $leftPre) { return 1 }
	if (-not $rightPre) { return -1 }

	$leftParts = $leftPre.Split('.')
	$rightParts = $rightPre.Split('.')
	for ($i = 0; $i -lt [Math]::Min($leftParts.Count, $rightParts.Count); $i++) {
		$leftNumeric = $leftParts[$i] -match '\A[0-9]+\z'
		$rightNumeric = $rightParts[$i] -match '\A[0-9]+\z'
		if ($leftNumeric -and $rightNumeric) {
			$comparison = ([decimal]$leftParts[$i]).CompareTo([decimal]$rightParts[$i])
		}
		elseif ($leftNumeric -ne $rightNumeric) {
			$comparison = if ($leftNumeric) { -1 } else { 1 }
		}
		else {
			$comparison = [string]::CompareOrdinal($leftParts[$i], $rightParts[$i])
		}
		if ($comparison -ne 0) { return $comparison }
	}
	return $leftParts.Count.CompareTo($rightParts.Count)
}

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
			if (Read-YesNo "A newer $workloadName version is available. Update it? [y/n]") {
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
Write-Host 'Starting project-specific packages...'
Write-Host

$packageCheckFailures = @{}
$downgradePackages = [System.Collections.Generic.List[string]]::new()
foreach ($tcpkgName in $installVersions.Keys) {
	try {
		$packageVersion = $installVersions[$tcpkgName]
		$installedPackages = @(Get-InstalledTcpkgPackage -PackageName $tcpkgName)
		if (@($installedPackages | Where-Object { $_.Version -eq $packageVersion }).Count -gt 0) {
			continue
		}
		$newerPackages = @($installedPackages | Where-Object {
			(Compare-TcpkgVersion -Left $_.Version -Right $packageVersion) -gt 0
		})
		if ($newerPackages.Count -gt 0) {
			$downgradePackages.Add("$tcpkgName`: installed $($newerPackages.Version -join ', '); requested $packageVersion")
		}
	}
	catch {
		$packageCheckFailures[$tcpkgName] = $true
		$installFailures.Add("Could not check ${tcpkgName}: $($_.Exception.Message)")
	}
}

$allowDowngrade = $false
if ($downgradePackages.Count -gt 0) {
	Write-Host "These packages have newer versions installed:"
	$downgradePackages | ForEach-Object { Write-Host "- $_" }
	Write-Host
	$allowDowngrade = Read-YesNo 'Allow all listed downgrades? Newer versions may be replaced if needed. Choose y to allow downgrades. [y/n]'
	Write-Host
}

$isFirstInstall = $true
foreach ($tcpkgName in $installVersions.Keys) {
	if ($packageCheckFailures.ContainsKey($tcpkgName)) {
		continue
	}
	$packageVersion = $installVersions[$tcpkgName]
	if (-not $isFirstInstall) {
		Write-Host
	}
	$isFirstInstall = $false
	try {
		$installedPackages = @(Get-InstalledTcpkgPackage -PackageName $tcpkgName)
		if (@($installedPackages | Where-Object { $_.Version -eq $packageVersion }).Count -gt 0) {
			Write-Host "$tcpkgName=$packageVersion is already installed"
			continue
		}

		$newerPackages = @($installedPackages | Where-Object {
			(Compare-TcpkgVersion -Left $_.Version -Right $packageVersion) -gt 0
		})
		if ($newerPackages.Count -gt 0 -and -not $allowDowngrade) {
			Write-Host "Skipping $tcpkgName=$packageVersion because a newer version is installed and downgrades were not approved"
			continue
		}

		Write-Host "Installing $tcpkgName=$packageVersion"
		$installArguments = @('install', '-y', "$tcpkgName=$packageVersion")
		if ($allowDowngrade) {
			$installArguments += '--allow-downgrade'
		}
		& tcpkg @installArguments
		if ($LASTEXITCODE -ne 0) {
			throw "tcpkg install failed (exit $LASTEXITCODE). Check configured tcpkg sources and package availability."
		}
		if (-not (Test-InstalledTcpkgPackage -PackageName $tcpkgName -PackageVersion $packageVersion)) {
			throw "tcpkg install completed but the requested version is not installed."
		}
	}
	catch {
		$installFailures.Add("Could not install ${tcpkgName}=${packageVersion}: $($_.Exception.Message)")
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
Write-Host 'Package download completed.'
Write-Host
Read-Host 'Press Enter to close'
