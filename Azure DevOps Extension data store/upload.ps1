<#
.SYNOPSIS
    Uploads a JSON document to the Azure DevOps Extension data store for an Azure DevOps extension.

.DESCRIPTION
    This script uses the Azure DevOps REST API to upload a JSON document to the extension's data store.
    It requires authentication via a Personal Access Token (PAT) and reads the JSON data from a specified input file.

.PARAMETER PersonalAccessToken
    The Personal Access Token for Azure DevOps authentication.

.PARAMETER Organization
    The Azure DevOps organization name.

.PARAMETER JsonFilePath
    The file path of the JSON file to upload.

.PARAMETER CollectionName
    The collection name in the data store (default: "$settings").

.PARAMETER DocumentId
    The ID of the document to upload. If not provided, uses the filename without extension.

.PARAMETER Scope
    The scope of the data (default: "User/Me"). Valid values: "User/Me", "Default/Current".

.PARAMETER BaseUrl
    The base URL for Azure DevOps (default: "https://dev.azure.com").

.PARAMETER publisherName
    The publisher name of the Azure DevOps extension

.PARAMETER extensionName
    The name of the Azure DevOps extension.

.EXAMPLE
    .\upload.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -JsonFilePath "input.json"

.NOTES
    Ensure you have the necessary permissions in Azure DevOps to modify the extension data.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PersonalAccessToken,

    [Parameter(Mandatory=$true)]
    [string]$Organization,

    [Parameter(Mandatory=$true)]
    [string]$JsonFilePath,

    [Parameter(Mandatory=$false)]
    [string]$CollectionName = "%24settings",

    [Parameter(Mandatory=$false)]
    [string]$DocumentId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("User/Me","Default/Current")]
    [string]$Scope = "User/Me",

    [Parameter(Mandatory=$false)]
    [string]$BaseUrl = "https://dev.azure.com",

    [Parameter(Mandatory=$true)]
    [string]$publisherName,

    [Parameter(Mandatory=$true)]
    [string]$extensionName
)


# Read the JSON file
if (-not (Test-Path $JsonFilePath)) {
    Write-Error "JSON file not found: $JsonFilePath"
    exit 1
}

$jsonContent = Get-Content $JsonFilePath -Raw | ConvertFrom-Json

# If DocumentId is not provided, use the filename without extension
if (-not $DocumentId) {
    $DocumentId = [System.IO.Path]::GetFileNameWithoutExtension($JsonFilePath)
}

$jsonContent.id = $DocumentId

# Construct the API URL
$baseUrl = "$BaseUrl/$Organization"
$apiUrl = "$baseUrl/_apis/ExtensionManagement/InstalledExtensions/$publisherName/$extensionName/Data/Scopes/$Scope/Collections/$CollectionName/Documents/$DocumentId"

# API Version
$apiVersion = "6.0-preview.1"
$apiUrl += "?api-version=$apiVersion"

Write-Verbose "API URL: $apiUrl"

# Prepare the request
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalAccessToken)"))
    "Content-Type" = "application/json"
}

# Convert JSON object back to string for the body
$body = $jsonContent | ConvertTo-Json -Depth 10

# Make the PUT request to upload the document
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $headers -Body $body -ContentType "application/json"
    Write-Host "Successfully uploaded JSON data to Azure DevOps datastore."
    Write-Host "Document ID: $($response.id)"
    Write-Host "ETag: $($response.__etag)"
} catch {
    Write-Error "Failed to upload data: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd()
        Write-Error "Response body: $responseBody"
    }
    exit 1
}
