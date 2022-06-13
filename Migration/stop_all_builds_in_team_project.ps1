# This script stops all running/notstarted builds in an Azd orga / team project collection

[CmdletBinding()]
param(
    [parameter(Mandatory = $true)]
    [Alias("CollectionUrl")]
    [string]$azdCollectionUrl,
    [parameter(Mandatory = $true)]
    [Alias("PersonalAccessToken")]
    [string]$pat,
    [parameter(Mandatory = $false)]
    [Alias("ProductionMode")]
    [bool]$prodMode = $false,
    [parameter(Mandatory = $false)]
    [string]$apiVersion = "6.0",
    [parameter(Mandatory = $false)]
    [string]$buildState= "notStarted")
    # Builds states: inProgress / notStarted

$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($pat)"))
$header = @{authorization = "Basic $token" }

#Go over all team projects
$projectsUrl = "$($azdCollectionUrl)/_apis/projects?api-version=6.0"
$projects = Invoke-RestMethod -Uri $projectsUrl -Method Get -Header $header -ContentType "application/json" 

foreach ($project in $projects.value) {

    write-host "Processing Team Project $($project.name)" -ForegroundColor Green
    $teamproject = $project.name;

    # Find all builds definitions in team project
    $buildDefsList = "$($azdCollectionUrl)/$($teamproject)/_apis/build/definitions?api-version=$($apiVersion)"
    $buildDefs = Invoke-RestMethod -Uri $buildDefsList -Method Get -Header $header -ContentType "application/json";
    $builds = @()

    foreach ($buildDef in $buildDefs.value|select id, name)
    {
    	# Find all builds in team project
    	$buildsUrl = "$($azdCollectionUrl)/$($teamproject)/_apis/build/builds?definitions=$($buildDef.id)&api-version=$($apiVersion)";
    	$buildsResult = Invoke-RestMethod -Uri $buildsUrl -Method Get -Header $header -ContentType "application/json";
    	$builds += $buildsResult;
    }

    # Calculating some statistics
    $affected = 0;
    $unaffected = 0;

    foreach ($b in $builds) {
        $affectedObjects = $builds.value.Where({ ($_.status -eq $buildState)});
        $affected = $affected + $affectedObjects.Count;
    }

    foreach ($b in $builds) {
        $unaffectedObjects = $builds.value.Where({ ($_.status -ne $buildState)});
        $unaffected = $unretained + $unaffectedObjects.Count;
    }

    write-host "Found $($builds.Count) builds in Team Project $teamproject";
    Write-Host "Found $($unaffected) builds without state $buildState";
    Write-Host "Found $($affected) builds with build state $buildState";

    $buildsToStop = $builds.value.Where({ ($_.status -eq $buildState)});
    ForEach ($build in $buildsToStop) {
	$buildObject = New-Object -TypeName PSObject;
        $buildObject | Add-Member -NotePropertyName status -NotePropertyValue Cancelling
	$buildJson = $buildObject | ConvertTo-Json
        
        $urlBuildToStop = "$($azdCollectionUrl)/$($teamproject)/_apis/build/builds/$($build.id)?api-version=$($apiVersion)";
        if ($prodMode) {
            Invoke-RestMethod -Uri $urlBuildToStop -Method Patch -ContentType application/json -Body $buildObject -Header $header;
            write-host "[ProductionMode] Cancelling the build $($build.buildnumber) - definitionname $($build.definition.name)"; 
        }
        else {
            write-host "[Dry-run without any change] Cancelling the build $($build.buildnumber) - definitionname $($build.definition.name)" -ForegroundColor DarkYellow;
        }
    }

    write-host "Found $($builds.Count) builds in Team Project $teamproject"
    Write-Host "Found $($unaffected) builds without state $buildState";
    Write-Host "Found $($affected) builds with build state $buildState";
}
