# AzureDevOpsScripts

Scripts for making your Azure DevOps life much easier.

## Repository Structure

| Area | Files |
| --- | --- |
| Azure DevOps Extension data store | [download.ps1](Azure%20DevOps%20Extension%20data%20store/download.ps1), [upload.ps1](Azure%20DevOps%20Extension%20data%20store/upload.ps1), [upload-from-csv.ps1](Azure%20DevOps%20Extension%20data%20store/upload-from-csv.ps1) |
| Banner | [banner-1.json](Banner/banner-1.json), [set_banners.ps1](Banner/set_banners.ps1) |
| Migration | [Delete_old_workspaces_older_than.linq](Migration/Delete_old_workspaces_older_than.linq), [Retain_All_Builds.ps1](Migration/Retain_All_Builds.ps1), [find_custom_fields.ps1](Migration/find_custom_fields.ps1), [install_collection_of_extensions_from_onpremise_to_cloud.ps1](Migration/install_collection_of_extensions_from_onpremise_to_cloud.ps1), [install_collection_of_extensions_from_source_org.ps1](Migration/install_collection_of_extensions_from_source_org.ps1), [stop_all_builds_in_team_project.ps1](Migration/stop_all_builds_in_team_project.ps1) |
| Wiki | [find_all_wiki_comments.ps1](Wiki/find_all_wiki_comments.ps1) |
| WorkItemTracking | [copy_wi_field_to_wi_field.ps1](WorkItemTracking/copy_wi_field_to_wi_field.ps1) |
| Root | [LICENSE](LICENSE), [README.md](README.md) |

## Script Purpose

| Script | Purpose |
| --- | --- |
| [Azure DevOps Extension data store/download.ps1](Azure%20DevOps%20Extension%20data%20store/download.ps1) | Downloads one extension data-store document from Azure DevOps and saves it as JSON. |
| [Azure DevOps Extension data store/upload.ps1](Azure%20DevOps%20Extension%20data%20store/upload.ps1) | Uploads one JSON document to an Azure DevOps extension data store (PUT). |
| [Azure DevOps Extension data store/upload-from-csv.ps1](Azure%20DevOps%20Extension%20data%20store/upload-from-csv.ps1) | Bulk uploads extension data-store documents from CSV rows (including debug/WhatIf support). |
| [Banner/set_banners.ps1](Banner/set_banners.ps1) | Replaces existing Azure DevOps global message banners with banners defined in local banner JSON files. |
| [Migration/Retain_All_Builds.ps1](Migration/Retain_All_Builds.ps1) | Sets keep-forever on builds (and adds a migration tag) to preserve build history during migration. |
| [Migration/find_custom_fields.ps1](Migration/find_custom_fields.ps1) | Lists custom work item fields by filtering out Microsoft/System fields via witadmin output. |
| [Migration/install_collection_of_extensions_from_onpremise_to_cloud.ps1](Migration/install_collection_of_extensions_from_onpremise_to_cloud.ps1) | Installs a list of extensions (from on-prem source data) into a target Azure DevOps cloud organization. |
| [Migration/install_collection_of_extensions_from_source_org.ps1](Migration/install_collection_of_extensions_from_source_org.ps1) | Copies installed extensions from one Azure DevOps organization to another using Azure DevOps CLI. |
| [Migration/stop_all_builds_in_team_project.ps1](Migration/stop_all_builds_in_team_project.ps1) | Cancels builds in a selected state (for example notStarted/inProgress) across team projects. |
| [Migration/Delete_old_workspaces_older_than.linq](Migration/Delete_old_workspaces_older_than.linq) | LINQPad script to find and delete old TFVC workspaces based on last access date. |
| [Wiki/find_all_wiki_comments.ps1](Wiki/find_all_wiki_comments.ps1) | Scans all projects/wikis and counts wiki comments, with summary by project and wiki. |
| [WorkItemTracking/copy_wi_field_to_wi_field.ps1](WorkItemTracking/copy_wi_field_to_wi_field.ps1) | Copies values from one custom work item field to another for matching work items. |

## Create CSV For Extension Data Store Upload

The script [Azure DevOps Extension data store/upload-from-csv.ps1](Azure%20DevOps%20Extension%20data%20store/upload-from-csv.ps1) expects a CSV with these columns:

- PublisherName
- ExtensionName
- DocumentIdText
- ScopeValueIdText
- DocumentValue
- CollectionName

Important: the first line in the CSV must contain these column names (header row).

One way to generate the CSV is to run this query in SQL Server Management Studio (SSMS)
against your Azure DevOps collection database, for example AzureDevOps_DefaultCollection,
and export the result set as CSV.

```sql
USE AzureDevOps_DefaultCollection;

SELECT
    [PublisherName],
    [ExtensionName],
    CONVERT(varchar(100), doc.DocumentId) AS DocumentIdText,
    CONVERT(varchar(100), col.ScopeValue) AS ScopeValueIdText,
    doc.DocumentValue,
    col.CollectionName
FROM [Extension].[tbl_ExtensionDataCollection] col
INNER JOIN [Extension].[tbl_ExtensionDataDocument] doc
    ON col.CollectionId = doc.CollectionId;
```

### Example CSV

```csv
PublisherName,ExtensionName,DocumentIdText,ScopeValueIdText,DocumentValue,CollectionName
myPublisher,myExtension,BuildPreferences,Current,"{""enabled"":true,""maxItems"":25}",$settings
```

### Example Script Calls

Dry-run (no upload), with debug output:

```powershell
.\upload-from-csv.ps1 \
    -PersonalAccessToken "<PAT>" \
    -Organization "my-org" \
    -CsvFilePath ".\extension-data.csv" \
    -WhatIf \
    -EnableDebugInfo
```

Real upload and show DocumentValue output:

```powershell
.\upload-from-csv.ps1 \
    -PersonalAccessToken "<PAT>" \
    -Organization "my-org" \
    -CsvFilePath ".\extension-data.csv" \
    -ScopeType "Default" \
    -ShowDocumentValue
```
