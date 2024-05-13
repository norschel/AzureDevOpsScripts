[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [Parameter(Mandatory = $true)]
    [string]$Project,
    [Parameter(Mandatory = $true)]
    [securestring]$Pat,
    [Parameter(Mandatory = $false)]
    [string]$newFieldRefName = "Custom.FieldNew",
    [Parameter(Mandatory = $false)]
    [string]$oldFieldRefName = "Custom.FieldOld"
)

write-host "Organization: $Organization"
write-host "Default Project: $Project"
write-host "This script will copy data from field $oldFieldRefName to field $newFieldRefName"

# Installation PowerShell Module
Write-Host "Installing and update latest VSTeam cmdlets"
Install-Module -Name VSTeam -Repository PSGallery -Scope CurrentUser
Update-Module -Name VSTeam
Import-Module -Name VSTeam
Write-Host "Installed latest version of VSTeam"

# Verbindung herstellen
$patPlainText = ConvertFrom-SecureString $Pat -AsPlainText
Set-VSTeamAccount -Account $Organization -PersonalAccessToken $patPlainText
Set-VSTeamDefaultProject $Project

# Work Items abfragen
$query = "Select [System.ID],[System.Title],$($oldFieldRefName) from WorkItems where [$($oldFieldRefName)] <> ''"
#$workitems = Get-VSTeamWiql -ProjectName $Project -Query "$query"
$workitems = Get-VSTeamWiql -Query "$query"

Write-Host "Found $($workitems.WorkItemIDs.Count) work items with field $($oldFieldRefName)"
Read-Host "Press any key to continue"

foreach ($workItemID in $workitems.WorkItemIDs) {
    $workitem = Get-VSTeamWorkItem -Id $workItemID -Fields $oldFieldRefName,System.Title
    write-host "Updating work item $($workItem.ID) - $($workitem.fields."System.Title")"
    $oldValue = $workItem.fields."$($oldFieldRefName)";
    $newValue = $oldValue;

    Write-Host "Old value ($($oldFieldRefName)): $($oldValue)"
    Write-Host "New value ($($newFieldRefName)): $($newValue)"

    # Work Item bearbeiten
    $additionalFields = @{"$($newFieldRefName)" = $newValue; "System.History" = "(Migration) Copied data from old field $($oldFieldRefName)"}
    Update-VSTeamWorkItem -ID $workItem.ID -AdditionalFields $additionalFields
    Write-Host "Update was successful"
}
