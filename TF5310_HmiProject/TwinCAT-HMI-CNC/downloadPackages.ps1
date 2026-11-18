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
	if ($Left -notmatch $pattern) { throw "Invalid package version: '$Left'" }
	$leftCore = $Matches.Core.Split('.')
	$leftPre = $Matches.Pre
	if ($Right -notmatch $pattern) { throw "Invalid package version: '$Right'" }
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

function Test-ExactVersion {
	param([string]$Version)

	# case sensitive on purpose, ignoring case lets a few non-ASCII letters pass as [A-Za-z]
	return $Version -cmatch '\A[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z'
}

function Test-PrereleaseVersion {
	param([string]$Version)

	return $Version -match '\A[0-9]+(?:\.[0-9]+){1,3}-'
}

function Get-LatestTcpkgVersion {
	param(
		[string]$PackageName,
		[bool]$IncludePrereleases
	)

	# all active feeds count, dev feeds too
	$listArguments = @('list', $PackageName, '--exact', '--all-sources', '--as-json')
	if ($IncludePrereleases) {
		$listArguments += '--include-prereleases'
	}
	$availablePackagesJson = & tcpkg @listArguments
	if ($LASTEXITCODE -ne 0) {
		throw "tcpkg list failed for $PackageName (exit $LASTEXITCODE): $($availablePackagesJson -join ' ')"
	}

	$availablePackagesText = $availablePackagesJson -join "`n"
	if ([string]::IsNullOrWhiteSpace($availablePackagesText)) {
		return $null
	}

	$latestVersion = $null
	foreach ($availablePackage in @(($availablePackagesText | ConvertFrom-Json -ErrorAction Stop) |
		Where-Object { $_.Id -eq $PackageName })) {
		$version = $availablePackage.Version
		# the version ends up in project files, so nothing but a plain version is accepted
		if (-not (Test-ExactVersion -Version $version)) {
			throw "tcpkg returned an invalid version for ${PackageName}: '$version'"
		}
		# stable only unless the configured version is a pre-release too
		if (-not $IncludePrereleases -and (Test-PrereleaseVersion -Version $version)) {
			continue
		}
		if ($null -eq $latestVersion -or (Compare-TcpkgVersion -Left $version -Right $latestVersion) -gt 0) {
			$latestVersion = $version
		}
	}
	return $latestVersion
}

function Get-NuGetFeedDirectory {
	# local feed that tcpkg fills with the HMI packages
	if ($env:ProgramData) {
		return Join-Path $env:ProgramData 'Beckhoff\NuGetPackages'
	}
}

function Test-NuGetPackageAvailable {
	param(
		[string]$PackageId,
		[string]$PackageVersion
	)

	# without the local feed there is nothing to check against
	$feedDirectory = Get-NuGetFeedDirectory
	if (-not $feedDirectory -or -not (Test-Path -LiteralPath $feedDirectory -PathType Container)) {
		return $true
	}
	# the version becomes part of a file name
	if (-not (Test-ExactVersion -Version $PackageVersion)) {
		return $false
	}
	return Test-Path -LiteralPath (Join-Path $feedDirectory "$PackageId.$PackageVersion.nupkg") -PathType Leaf
}

# ISO-8859-1 maps every byte to one char, so files can be edited as text without touching other bytes (BOM, encoding, line endings)
$byteEncoding = [System.Text.Encoding]::GetEncoding(28591)

# project files besides packages.config that hard-code package folder versions
$projectVersionFiles = @(
	@{ Directory = ''; Filter = '*.hmiproj' }
	@{ Directory = ''; Filter = 'tsconfig.json' }
	@{ Directory = 'Properties'; Filter = 'tchmiconfig.json' }
	@{ Directory = 'Server\TcHmiSrv'; Filter = 'TcHmiSrv.Config*.json' }
	@{ Directory = 'Localization'; Filter = '*.localization' }
	@{ Directory = 'Themes'; Filter = '*.theme'; Recurse = $true }
)

function Get-PackagesConfigVersions {
	param([byte[]]$Content)

	# no DTD and no resolver, a project file must not make the script load other files or addresses
	$settings = New-Object System.Xml.XmlReaderSettings
	$settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
	$settings.XmlResolver = $null
	$stream = New-Object System.IO.MemoryStream -ArgumentList (, $Content)
	$reader = [System.Xml.XmlReader]::Create($stream, $settings)
	try {
		$document = New-Object System.Xml.XmlDocument
		$document.Load($reader)
	}
	finally {
		$reader.Dispose()
		$stream.Dispose()
	}

	$versions = @{}
	foreach ($package in $document.SelectNodes('/packages/package')) {
		$versions[$package.GetAttribute('id')] = $package.GetAttribute('version')
	}
	return $versions
}

function Get-ProjectVersionUpdatePlan {
	param(
		[string]$PackagesConfigPath,
		[object[]]$PackageUpgrades
	)

	# the versions get written into project files, so nothing but plain versions is accepted
	foreach ($upgrade in $PackageUpgrades) {
		if (-not (Test-ExactVersion -Version $upgrade.OldVersion) -or -not (Test-ExactVersion -Version $upgrade.NewVersion)) {
			throw "Unexpected version for $($upgrade.Id): '$($upgrade.OldVersion)' -> '$($upgrade.NewVersion)'"
		}
	}

	$ignoreCase = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
	$configPath = (Resolve-Path -LiteralPath $PackagesConfigPath).ProviderPath
	$projectDirectory = Split-Path -Parent $configPath
	$plan = [System.Collections.Generic.List[object]]::new()

	$originalConfig = [System.IO.File]::ReadAllBytes($configPath)
	$configText = $byteEncoding.GetString($originalConfig)
	foreach ($upgrade in $PackageUpgrades) {
		$packageElement = $null
		foreach ($element in [regex]::Matches($configText, '<package\b[^>]*>')) {
			if ($element.Value -match ('\bid\s*=\s*([''"])' + [regex]::Escape($upgrade.Id) + '\1')) {
				$packageElement = $element
				break
			}
		}
		if ($null -eq $packageElement) {
			throw "Package $($upgrade.Id) not found in $configPath"
		}

		$versionPattern = '(?<head>\bversion\s*=\s*(?<quote>[''"]))' + [regex]::Escape($upgrade.OldVersion) + '\k<quote>'
		$updatedElement = [regex]::Replace($packageElement.Value, $versionPattern, ('${head}' + $upgrade.NewVersion + '${quote}'))
		if ($updatedElement -ceq $packageElement.Value) {
			throw "Version $($upgrade.OldVersion) of $($upgrade.Id) not found in $configPath"
		}
		$configText = $configText.Substring(0, $packageElement.Index) + $updatedElement + $configText.Substring($packageElement.Index + $packageElement.Length)
	}

	# packages.config has to stay valid and only the requested versions may differ
	$updatedConfig = $byteEncoding.GetBytes($configText)
	$originalVersions = Get-PackagesConfigVersions -Content $originalConfig
	$updatedVersions = Get-PackagesConfigVersions -Content $updatedConfig
	if ($updatedVersions.Count -ne $originalVersions.Count) {
		throw "Unexpected result when updating $configPath"
	}
	foreach ($packageId in $originalVersions.Keys) {
		$expectedVersion = $originalVersions[$packageId]
		foreach ($upgrade in $PackageUpgrades) {
			if ($upgrade.Id -eq $packageId) {
				$expectedVersion = $upgrade.NewVersion
			}
		}
		if ($updatedVersions[$packageId] -cne $expectedVersion) {
			throw "Unexpected result when updating $packageId in $configPath"
		}
	}
	foreach ($selector in $projectVersionFiles) {
		$directory = Join-Path $projectDirectory $selector.Directory
		if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
			continue
		}

		foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter $selector.Filter -File -Recurse:([bool]$selector.Recurse))) {
			$originalContent = [System.IO.File]::ReadAllBytes($file.FullName)
			$text = $byteEncoding.GetString($originalContent)
			$referenceCount = 0
			foreach ($upgrade in $PackageUpgrades) {
				# only package folder paths like ..\Packages\<id>.<version>\ count as reference
				$referencePattern = '(?<=[\\/])(?<id>' + [regex]::Escape($upgrade.Id) + ')\.' + [regex]::Escape($upgrade.OldVersion) + '(?![0-9A-Za-z-]|\.[0-9])'
				$referenceCount += [regex]::Matches($text, $referencePattern, $ignoreCase).Count
				$text = [regex]::Replace($text, $referencePattern, ('${id}.' + $upgrade.NewVersion), $ignoreCase)
			}
			if ($referenceCount -gt 0) {
				$plan.Add([pscustomobject]@{
					Path = $file.FullName
					Name = $file.FullName.Substring($projectDirectory.Length).TrimStart('\', '/')
					OriginalBytes = $originalContent
					UpdatedBytes = $byteEncoding.GetBytes($text)
				})
			}
		}
	}

	# last, so a run that gets interrupted while writing can simply be repeated
	$plan.Add([pscustomobject]@{
		Path = $configPath
		Name = Split-Path -Leaf $configPath
		OriginalBytes = $originalConfig
		UpdatedBytes = $updatedConfig
	})
	return $plan
}

function Save-ProjectVersionUpdatePlan {
	param([object[]]$Plan)

	$attemptedFiles = [System.Collections.Generic.List[object]]::new()
	$completed = $false
	try {
		foreach ($file in $Plan) {
			$attemptedFiles.Add($file)
			[System.IO.File]::WriteAllBytes($file.Path, $file.UpdatedBytes)
		}
		$completed = $true
	}
	finally {
		# runs on Ctrl+C too, put the files back so the project is not left half updated
		if (-not $completed) {
			$restoredFiles = 0
			$notRestoredFiles = [System.Collections.Generic.List[string]]::new()
			foreach ($file in $attemptedFiles) {
				try {
					if ($byteEncoding.GetString([System.IO.File]::ReadAllBytes($file.Path)) -cne $byteEncoding.GetString($file.OriginalBytes)) {
						[System.IO.File]::WriteAllBytes($file.Path, $file.OriginalBytes)
						$restoredFiles++
					}
				}
				catch {
					$notRestoredFiles.Add($file.Name)
				}
			}

			if ($notRestoredFiles.Count -gt 0) {
				Write-Warning "Could not restore $($notRestoredFiles -join ', '), check these files before using the project"
			}
			elseif ($restoredFiles -gt 0) {
				Write-Host "Restored $restoredFiles project file(s) to their previous state"
			}
			else {
				Write-Host 'No project file was changed'
			}
		}
	}
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
	if (-not (Test-ExactVersion -Version $packageVersion)) {
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

# these stay at the configured version and are not checked for newer ones
$noUpgradePackages = @('TypeScript.Beckhoff')
$packagesToCheck = @($installVersions.Keys | Where-Object { $noUpgradePackages -notcontains $_ })

# one dot per package in plain text, a progress bar would cover the output above
Write-Host "Checking $($packagesToCheck.Count) packages for newer versions " -NoNewline
$latestVersions = [ordered]@{}
$checkWarnings = [System.Collections.Generic.List[string]]::new()
foreach ($tcpkgName in $packagesToCheck) {
	$configuredVersion = $installVersions[$tcpkgName]
	try {
		$latestVersion = Get-LatestTcpkgVersion -PackageName $tcpkgName -IncludePrereleases (Test-PrereleaseVersion -Version $configuredVersion)
		if ($latestVersion -and (Compare-TcpkgVersion -Left $latestVersion -Right $configuredVersion) -gt 0) {
			$latestVersions[$tcpkgName] = $latestVersion
		}
		Write-Host '.' -NoNewline
	}
	catch {
		Write-Host 'x' -NoNewline
		$checkWarnings.Add("Could not check $tcpkgName for a newer version: $($_.Exception.Message)")
	}
}
Write-Host
$checkWarnings | ForEach-Object { Write-Warning $_ }

# tcpkg name -> upgrades of the packages.config entries it provides, only filled when the user accepts
$acceptedUpgrades = [ordered]@{}
if ($latestVersions.Count -eq 0) {
	if ($checkWarnings.Count -eq 0) {
		Write-Host 'No newer package versions available'
	}
	Write-Host
}
else {
	$upgradeCandidates = [ordered]@{}
	foreach ($tcpkgName in $latestVersions.Keys) {
		$upgradeCandidates[$tcpkgName] = @(foreach ($packageId in @($packageVersions.Keys | Where-Object { $packageMapping[$_] -eq $tcpkgName } | Sort-Object)) {
			[pscustomobject]@{
				Id = $packageId
				OldVersion = $packageVersions[$packageId]
				NewVersion = $latestVersions[$tcpkgName]
			}
		})
	}

	try {
		$previewPlan = @(Get-ProjectVersionUpdatePlan -PackagesConfigPath $PackagesConfigPath -PackageUpgrades @($upgradeCandidates.Values | ForEach-Object { $_ }))
	}
	catch {
		$previewPlan = @()
		Write-Warning "Newer package versions are available, but the project configuration cannot be updated: $($_.Exception.Message)"
		Write-Host
	}

	if ($previewPlan.Count -gt 0) {
		Write-Host 'These packages have newer versions available:'
		foreach ($tcpkgName in $latestVersions.Keys) {
			Write-Host "- $tcpkgName`: $($installVersions[$tcpkgName]) -> $($latestVersions[$tcpkgName])"
		}
		Write-Host
		Write-Host 'To use the newer versions, the project configuration has to be updated as well. These files will be changed:'
		$previewPlan | ForEach-Object { Write-Host "- $($_.Name)" }
		Write-Host
		if (Read-YesNo 'Use the newer versions and update the project configuration? [y/n]') {
			foreach ($tcpkgName in $latestVersions.Keys) {
				$acceptedUpgrades[$tcpkgName] = $upgradeCandidates[$tcpkgName]
				$installVersions[$tcpkgName] = $latestVersions[$tcpkgName]
			}
		}
		else {
			Write-Host 'Keeping the package versions from packages.config'
		}
		Write-Host
	}
}

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

$readyPackages = @{}
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
			$readyPackages[$tcpkgName] = $true
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
		$readyPackages[$tcpkgName] = $true
	}
	catch {
		$installFailures.Add("Could not install ${tcpkgName}=${packageVersion}: $($_.Exception.Message)")
	}
}

if ($acceptedUpgrades.Count -gt 0) {
	Write-Host
	$appliedUpgrades = @()
	foreach ($tcpkgName in $acceptedUpgrades.Keys) {
		$packageUpgrades = $acceptedUpgrades[$tcpkgName]
		$oldVersion = $packageUpgrades[0].OldVersion
		$newVersion = $packageUpgrades[0].NewVersion

		$keepReason = $null
		if (-not $readyPackages.ContainsKey($tcpkgName)) {
			$keepReason = "$newVersion is not installed"
		}
		else {
			# the NuGet packages need the version of the tcpkg package, check that before writing it into the project
			$missingPackages = @($packageUpgrades | Where-Object { -not (Test-NuGetPackageAvailable -PackageId $_.Id -PackageVersion $_.NewVersion) } | ForEach-Object { $_.Id })
			if ($missingPackages.Count -gt 0) {
				$keepReason = "version $newVersion of $($missingPackages -join ', ') was not found in $(Get-NuGetFeedDirectory)"
				$installFailures.Add("$tcpkgName=$newVersion is installed, but $keepReason.")
			}
		}

		if (-not $keepReason) {
			$appliedUpgrades += $packageUpgrades
			continue
		}

		Write-Host "Keeping $tcpkgName=$oldVersion in the project configuration because $keepReason"
		# the version that stays in packages.config has to be installed, otherwise the project can not be restored
		try {
			if (-not (Test-InstalledTcpkgPackage -PackageName $tcpkgName -PackageVersion $oldVersion)) {
				$installFailures.Add("${tcpkgName}=${oldVersion} stays in packages.config but is not installed. Run the script again and answer y to retry the upgrade or n to install $oldVersion.")
			}
		}
		catch {
			$installFailures.Add("Could not check whether ${tcpkgName}=${oldVersion} is installed: $($_.Exception.Message)")
		}
	}

	if ($appliedUpgrades.Count -gt 0) {
		try {
			$finalPlan = @(Get-ProjectVersionUpdatePlan -PackagesConfigPath $PackagesConfigPath -PackageUpgrades $appliedUpgrades)
			Save-ProjectVersionUpdatePlan -Plan $finalPlan
			Write-Host 'Updated the project configuration to the newer package versions:'
			$appliedUpgrades | ForEach-Object { Write-Host "- $($_.Id): $($_.OldVersion) -> $($_.NewVersion)" }
			Write-Host
			Write-Host 'Changed files:'
			$finalPlan | ForEach-Object { Write-Host "- $($_.Name)" }
			Write-Host
			Write-Host 'Reload the project in Visual Studio or TwinCAT XAE if it is open.'
		}
		catch {
			$installFailures.Add("Could not update the project configuration: $($_.Exception.Message)")
		}
	}
}

if ($installFailures.Count -gt 0) {
	throw "One or more tcpkg installs or project updates failed:`n- $($installFailures -join "`n- ")"
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
