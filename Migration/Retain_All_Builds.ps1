# This script sets the keep forever for all builds in an Azd orga / team project collection
# Keep forever flag is only set if build run does not have this flag
# Additionaly it adds an build-tag so you know which builds have be marked

# This script was build for making migration to Azure DevOps easier because pipeline/build specific retention policies are not supported in the cloud.
# Builds with forever flag are still supported in the cloud and won't be deleted.

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
    [Alias("BuildTag")]
    [string]$migrationTag = "CloudMigration",
    [parameter(Mandatory = $false)]
    [string]$apiVersion = "6.0",
    [parameter(Mandatory = $false)]
    [string]$SnapshotName)

$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($pat)"))
$header = @{authorization = "Basic $token" }

#Go over all team projects
$projectsUrl = "$($azdCollectionUrl)/_apis/projects?api-version=6.0"
$projects = Invoke-RestMethod -Uri $projectsUrl -Method Get -Header $header -ContentType "application/json" 

foreach ($project in $projects.value) {

    write-host "Processing Team Project $($project.name)" -ForegroundColor Green

    $teamproject = $project.name;

    # Find all builds in team project
    $buildsUrl = "$($azdCollectionUrl)/$($teamproject)/_apis/build/builds?api-version=$($apiVersion)";
    $builds = Invoke-RestMethod -Uri $buildsUrl -Method Get -Header $header -ContentType "application/json"; 

    # Calculating some statistics
    $unretained = 0;
    $retained = 0;

    foreach ($b in $builds) {
        $retainedObjects = $builds.value.Where({ ($_.keepForever -eq $True) })
        $retained = $retained + $retainedObjects.Count;
    }

    foreach ($b in $builds) {
        $unretainedObjects = $builds.value.Where({ ($_.keepForever -eq $False) })
        $unretained = $unretained + $unretainedObjects.Count;
    }

    write-host "Found $($builds.Count) builds in Team Project"
    Write-Host "Found $($unretained) builds without retain flag";
    Write-Host "Found $($retained) builds with retain flag";

    $buildsToRetain = $builds.value.Where({ ($_.keepForever -eq $False) })
    ForEach ($build in $buildsToRetain) {
        # Add a tag so we know which builds have been tagged
        $addTagUrl = "$($azdCollectionUrl)/$($teamproject)/_apis/build/builds/$($build.id)/tags/$($migrationTag)?api-version=$($apiVersion)";
        if ($prodMode) {
            Invoke-RestMethod -Uri $addTagUrl -Method Put -Header $header -ContentType "application/json";
            write-host "[ProductionMode] Adding tag $($migrationTag) to buildnumber $($build.buildnumber) - definitionname $($build.definition.name)"; 
        }
        else {
            write-host "[Dry-run without any change] Adding tag $($migrationTag) to buildnumber $($build.buildnumber) - definitionname $($build.definition.name)" -ForegroundColor DarkYellow;
        }

        # Final step: set keepforever flag to true
		$buildObject = New-Object -TypeName PSObject;
		$buildObject | Add-Member -NotePropertyName keepForever -NotePropertyValue $True
		$buildJson = $buildObject | ConvertTo-Json
        
        $urlBuildRetain = "$($azdCollectionUrl)/$($teamproject)/_apis/build//builds/$($build.id)?api-version=$($apiVersion)";
        if ($prodMode) {
            Invoke-RestMethod -Uri $urlBuildRetain -Method Patch -ContentType application/json -Body $buildObject -Header $header;
            write-host "[ProductionMode] Set KeepForever of buildnumber $($build.buildnumber) - $($build.definition.name) to true (keep it forever)"; 
        }
        else {
            write-host "[Dry-run without any change] Set KeepForever of buildnumber $($build.buildnumber) - definitionname $($build.definition.name) to true (keep it forever)" -ForegroundColor DarkYellow;
        }
    }
}
