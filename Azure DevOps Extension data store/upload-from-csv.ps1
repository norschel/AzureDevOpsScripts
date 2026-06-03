<#
.SYNOPSIS
    Uploads documents from a CSV file to the Azure DevOps Extension data store.

.DESCRIPTION
    This script reads a CSV file with extension data store entries and uploads each
    row as a document via the Azure DevOps REST API (PUT).
    The first CSV row must contain the column headers.
    The CSV must contain the following columns:
        PublisherName    - Publisher ID of the extension
        ExtensionName    - Name/ID of the extension
        DocumentIdText   - Document ID
        ScopeValueIdText - Scope value, e.g. "Current" (combined with ScopeType to form "Default/Current")
        DocumentValue    - JSON string of the document body
        CollectionName   - Collection name in the data store

.PARAMETER PersonalAccessToken
    The Personal Access Token for Azure DevOps authentication.

.PARAMETER Organization
    The Azure DevOps organization name.

.PARAMETER CsvFilePath
    The path to the CSV file to import.

.PARAMETER CsvDelimiter
    The delimiter used in the CSV file (default: ",").

.PARAMETER ScopeType
    The scope type to prepend to the ScopeValueIdText column value (default: "Default").
    Together they form the scope path segment, e.g. "Default/Current" or "User/Me".

.PARAMETER ApiVersion
    The Azure DevOps REST API version to use (default: "7.2-preview.1").

.PARAMETER BaseUrl
    The base URL for Azure DevOps extension management API
    (default: "https://extmgmt.dev.azure.com").

.PARAMETER WhatIf
    When specified, the script logs what it would do without sending any requests.

.PARAMETER EnableDebugInfo
    When specified, emits additional debug information to help troubleshooting.

.PARAMETER ShowDocumentValue
    When specified, includes the serialized DocumentValue content in output.

.EXAMPLE
    .\upload-from-csv.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -CsvFilePath "data.csv"

.EXAMPLE
    .\upload-from-csv.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -CsvFilePath "data.csv" -CsvDelimiter ";" -WhatIf

.EXAMPLE
    .\upload-from-csv.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -CsvFilePath "data.csv" -WhatIf -EnableDebugInfo -ShowDocumentValue

.EXAMPLE
    .\upload-from-csv.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -CsvFilePath ".\extension-data.csv" -ScopeType "Default" -EnableDebugInfo

.NOTES
    Ensure you have the necessary permissions in Azure DevOps to modify the extension data.
    Each row in the CSV results in one PUT request to the data store API.
    Important: The first CSV row must be the header row with the expected column names.
    CSV creation hint:
    The source CSV can be exported from SQL Server Management Studio (SSMS).
    Example query (database: AzureDevOps_DefaultCollection):

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
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PersonalAccessToken,

    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$CsvFilePath,

    [Parameter(Mandatory = $false)]
    [string]$CsvDelimiter = ",",

    [Parameter(Mandatory = $false)]
    [string]$ScopeType = "Default",

    [Parameter(Mandatory = $false)]
    [string]$ApiVersion = "7.2-preview.1",

    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = "https://extmgmt.dev.azure.com",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [switch]$EnableDebugInfo,

    [Parameter(Mandatory = $false)]
    [switch]$ShowDocumentValue
)

function Write-DebugInfo {
    param([string]$Message)

    if ($EnableDebugInfo) {
        Write-Host "[Debug] $Message"
    }
}

# Validate CSV file exists
if (-not (Test-Path -Path $CsvFilePath -PathType Leaf)) {
    Write-Error "CSV file not found: $CsvFilePath"
    exit 1
}

Write-DebugInfo "CsvFilePath=$CsvFilePath"
Write-DebugInfo "CsvDelimiter='$CsvDelimiter' ScopeType='$ScopeType' ApiVersion='$ApiVersion' BaseUrl='$BaseUrl' WhatIf=$WhatIf ShowDocumentValue=$ShowDocumentValue"

# Read CSV
$rows = Import-Csv -Path $CsvFilePath -Delimiter $CsvDelimiter

if ($rows.Count -eq 0) {
    Write-Warning "CSV file contains no data rows. Nothing to upload."
    exit 0
}

Write-DebugInfo "Loaded $($rows.Count) row(s) from CSV"

# Validate required columns
$requiredColumns = @(
    "PublisherName",
    "ExtensionName",
    "DocumentIdText",
    "ScopeValueIdText",
    "DocumentValue",
    "CollectionName"
)

$csvColumns = $rows[0].PSObject.Properties.Name
foreach ($col in $requiredColumns) {
    if ($col -notin $csvColumns) {
        Write-Error "CSV is missing required column: '$col'. Found columns: $($csvColumns -join ', '). The first CSV row must contain the column names/header."
        exit 1
    }
}

Write-DebugInfo "CSV schema validation passed"

# Prepare auth header
$authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
$headers = @{
    Authorization = $authHeader
    "Content-Type" = "application/json"
}

$successCount = 0
$failureCount = 0
$rowIndex = 0

foreach ($row in $rows) {
    $rowIndex++

    $publisherName = $row.PublisherName
    $extensionName = $row.ExtensionName
    $documentId = $row.DocumentIdText
    $scopeValue = $row.ScopeValueIdText
    $documentValue = $row.DocumentValue
    $collectionName = $row.CollectionName

    # Build full scope path: e.g. "Default/Current" or "User/Me"
    $scopePath = "$ScopeType/$scopeValue"

    # URL-encode the collection name (handles leading '$' and other special chars)
    $encodedCollection = [Uri]::EscapeDataString($collectionName)

    # Construct the API URL
    $apiUrl = "$BaseUrl/$Organization/_apis/ExtensionManagement/InstalledExtensions/$publisherName/$extensionName/Data/Scopes/$scopePath/Collections/$encodedCollection/Documents`?api-version=$ApiVersion"

    Write-DebugInfo "Row $rowIndex - Publisher='$publisherName' Extension='$extensionName' DocumentId='$documentId' ScopePath='$scopePath' Collection='$collectionName'"
    Write-Verbose "Row $rowIndex - API URL: $apiUrl"

    # Parse DocumentValue to ensure it is valid JSON
    try {
        $docObject = $documentValue | ConvertFrom-Json
    }
    catch {
        Write-Warning "Row $rowIndex - DocumentValue is not valid JSON. Skipping row. Error: $($_.Exception.Message)"
        $failureCount++
        continue
    }

    # Use optimistic concurrency marker to force update behavior.
    $docObject.__etag = "-1"
    $body = $docObject | ConvertTo-Json -Depth 20

    if ($WhatIf) {
        Write-Host "[WhatIf] Row $rowIndex - Would PUT to: $apiUrl"

        if ($ShowDocumentValue) {
            Write-Host "[WhatIf] Row $rowIndex - Body: $body"
        }
        else {
            Write-Host "[WhatIf] Row $rowIndex - Body: <hidden; use -ShowDocumentValue to display>"
        }

        $successCount++
        continue
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "Row $rowIndex - OK  Publisher=$publisherName Extension=$extensionName DocId=$documentId ETag=$($response.__etag)"

        if ($ShowDocumentValue) {
            Write-Host "Row $rowIndex - DocumentValue: $body"
        }

        $successCount++
    }
    catch {
        Write-DebugInfo "Row $rowIndex - Request URL: $apiUrl"
        Write-Warning "Row $rowIndex - FAILED  Publisher=$publisherName Extension=$extensionName DocId=$documentId Error=$($_.Exception.Message)"
        $failureCount++
    }
}

Write-Host ""
Write-Host "Upload complete. Success: $successCount  Failed: $failureCount  Total: $rowIndex"

if ($failureCount -gt 0) {
    exit 1
}