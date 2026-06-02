<#
.SYNOPSIS
    Uploads documents from a CSV file to the Azure DevOps Extension data store.

.DESCRIPTION
    This script reads a CSV file with extension data store entries and uploads each
    row as a document via the Azure DevOps REST API (PUT).
    The CSV must contain the following columns:
        PublisherName     - Publisher ID of the extension
        ExtensionName     - Name/ID of the extension
        DocumentIdText    - Document ID
        ScopeValueIdText  - Scope value, e.g. "Current" (combined with ScopeType to form "Default/Current")
        DocumentValue     - JSON string of the document body
        CollectionName    - Collection name in the data store

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

.PARAMETER BaseUrl
    The base URL for Azure DevOps (default: "https://dev.azure.com").

.PARAMETER WhatIf
    When specified, the script logs what it would do without sending any requests.

.EXAMPLE
    .\upload-from-csv.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -CsvFilePath "data.csv"

.EXAMPLE
    .\upload-from-csv.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -CsvFilePath "data.csv" -CsvDelimiter ";" -WhatIf

.NOTES
    Ensure you have the necessary permissions in Azure DevOps to modify the extension data.
    Each row in the CSV results in one PUT request to the data store API.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PersonalAccessToken,

    [Parameter(Mandatory=$true)]
    [string]$Organization,

    [Parameter(Mandatory=$true)]
    [string]$CsvFilePath,

    [Parameter(Mandatory=$false)]
    [string]$CsvDelimiter = ",",

    [Parameter(Mandatory=$false)]
    [string]$ScopeType = "Default",

    [Parameter(Mandatory=$false)]
    [string]$BaseUrl = "https://dev.azure.com",

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Validate CSV file exists
if (-not (Test-Path $CsvFilePath)) {
    Write-Error "CSV file not found: $CsvFilePath"
    exit 1
}

# Read CSV
$rows = Import-Csv -Path $CsvFilePath -Delimiter $CsvDelimiter

# Validate required columns
$requiredColumns = @("PublisherName", "ExtensionName", "DocumentIdText", "ScopeValueIdText", "DocumentValue", "CollectionName")
$csvColumns = $rows[0].PSObject.Properties.Name
foreach ($col in $requiredColumns) {
    if ($col -notin $csvColumns) {
        Write-Error "CSV is missing required column: '$col'. Found columns: $($csvColumns -join ', ')"
        exit 1
    }
}

# Prepare auth header
$authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))
$headers = @{
    "Authorization" = $authHeader
    "Content-Type"  = "application/json"
}

# API Version
$apiVersion = "6.0-preview.1"

$successCount = 0
$failureCount = 0
$rowIndex = 0

foreach ($row in $rows) {
    $rowIndex++

    $publisherName  = $row.PublisherName
    $extensionName  = $row.ExtensionName
    $documentId     = $row.DocumentIdText
    $scopeValue     = $row.ScopeValueIdText
    $documentValue  = $row.DocumentValue
    $collectionName = $row.CollectionName

    # Build full scope path: e.g. "Default/Current" or "User/Me"
    $scopePath = "$ScopeType/$scopeValue"

    # URL-encode the collection name (handle leading $ sign)
    $encodedCollection = [Uri]::EscapeDataString($collectionName)

    # Construct the API URL
    $apiUrl = "$BaseUrl/$Organization/_apis/ExtensionManagement/InstalledExtensions/$publisherName/$extensionName/Data/Scopes/$scopePath/Collections/$encodedCollection/Documents/$documentId`?api-version=$apiVersion"

    Write-Verbose "Row $rowIndex - API URL: $apiUrl"

    # Parse DocumentValue to ensure it is valid JSON, then inject the document id
    try {
        $docObject = $documentValue | ConvertFrom-Json
    } catch {
        Write-Warning "Row $rowIndex - DocumentValue is not valid JSON. Skipping row. Error: $($_.Exception.Message)"
        $failureCount++
        continue
    }

    # Set / overwrite the id field inside the document body as required by the API
    $docObject | Add-Member -MemberType NoteProperty -Name "id" -Value $documentId -Force

    $body = $docObject | ConvertTo-Json -Depth 20 -Compress

    if ($WhatIf) {
        Write-Host "[WhatIf] Row $rowIndex - Would PUT to: $apiUrl"
        Write-Host "[WhatIf] Row $rowIndex - Body: $body"
        $successCount++
        continue
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "Row $rowIndex - OK  Publisher=$publisherName Extension=$extensionName DocId=$documentId ETag=$($response.__etag)"
        $successCount++
    } catch {
        Write-Warning "Row $rowIndex - FAILED  Publisher=$publisherName Extension=$extensionName DocId=$documentId Error=$($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd()
                Write-Warning "Row $rowIndex - Response body: $responseBody"
            } catch {}
        }
        $failureCount++
    }
}

Write-Host ""
Write-Host "Upload complete. Success: $successCount  Failed: $failureCount  Total: $rowIndex"

if ($failureCount -gt 0) {
    exit 1
}
