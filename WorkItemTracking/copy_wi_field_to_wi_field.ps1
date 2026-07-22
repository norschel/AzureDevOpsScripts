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
    [string]$oldFieldRefName = "Custom.FieldOld",
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    [Parameter(Mandatory = $false)]
    [switch]$Override
)

Write-Host "Organization: $Organization"
Write-Host "Default Project: $Project"
Write-Host "This script will copy data from field $oldFieldRefName to field $newFieldRefName"
Write-Host "DryRun: $DryRun | Override: $Override"

# Counters
[int]$updatedCount = 0
[int]$skippedCount = 0
[int]$dryRunCount = 0
[int]$failedCount = 0

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
$query = "Select [System.ID],[System.Title],[$($oldFieldRefName)],[$($newFieldRefName)] from WorkItems where [$($oldFieldRefName)] <> ''"
$workitems = Get-VSTeamWiql -Query "$query"

Write-Host "Found $($workitems.WorkItemIDs.Count) work items with field $($oldFieldRefName)"
Read-Host "Press any key to continue"

foreach ($workItemID in $workitems.WorkItemIDs) {
    try {
        $workitem = Get-VSTeamWorkItem -Id $workItemID -Fields $oldFieldRefName,$newFieldRefName,System.Title
        Write-Host "Processing work item $($workItem.ID) - $($workitem.fields.'System.Title')"

        $oldValue = $workItem.fields."$($oldFieldRefName)"
        $currentNewValue = $workItem.fields."$($newFieldRefName)"

        Write-Host "Old value ($($oldFieldRefName)): $oldValue"
        Write-Host "Current target value ($($newFieldRefName)): $currentNewValue"

        # Skip if target already has value and override is not set
        if (-not [string]::IsNullOrWhiteSpace([string]$currentNewValue) -and -not $Override) {
            Write-Host "Skipping work item $($workItem.ID): target field '$newFieldRefName' already has a value. Use -Override to force update."
            $skippedCount++
            continue
        }

        $additionalFields = @{
            "$($newFieldRefName)" = $oldValue
            "System.History"      = "(Migration) Copied data from old field $($oldFieldRefName)"
        }

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would update work item $($workItem.ID): set '$newFieldRefName' to '$oldValue'"
            $dryRunCount++
            continue
        }

        Update-VSTeamWorkItem -ID $workItem.ID -AdditionalFields $additionalFields
        Write-Host "Update was successful"
        $updatedCount++
    }
    catch {
        Write-Host "Failed to process work item $workItemID. Error: $($_.Exception.Message)"
        $failedCount++
    }
}

Write-Host ""
Write-Host "========== Summary =========="
Write-Host "Total found:     $($workitems.WorkItemIDs.Count)"
Write-Host "Updated:         $updatedCount"
Write-Host "Skipped:         $skippedCount"
Write-Host "Dry-run simulated: $dryRunCount"
Write-Host "Failed:          $failedCount"
Write-Host "============================="
