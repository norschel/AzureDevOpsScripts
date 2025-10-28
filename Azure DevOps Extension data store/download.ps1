<#
.SYNOPSIS
    Downloads a JSON document from the Azure DevOps Extension data store for an Azure DevOps extension.

.DESCRIPTION
    This script uses the Azure DevOps REST API to retrieve a specific document from the extension's data store.
    It requires authentication via a Personal Access Token (PAT) and saves the downloaded JSON data to a specified output file.

.PARAMETER PersonalAccessToken
    The Personal Access Token for Azure DevOps authentication.

.PARAMETER Organization
    The Azure DevOps organization name.

.PARAMETER OutputFilePath
    The file path where the downloaded JSON data will be saved.

.PARAMETER CollectionName
    The collection name in the data store (default: "$settings").

.PARAMETER DocumentId
    The ID of the document to download.

.PARAMETER Scope
    The scope of the data (default: "User/Me"). Valid values: "User/Me", "Default/Current".

.PARAMETER BaseUrl
    The base URL for Azure DevOps (default: "https://dev.azure.com").

.PARAMETER publisherName
    The publisher name of the Azure DevOps extension.

.PARAMETER extensionName
    The name of the Azure DevOps extension.

.EXAMPLE
    .\download.ps1 -PersonalAccessToken "your-pat" -Organization "your-org" -OutputFilePath "output.json" -DocumentId "your-doc-id" -publisherName "<publisherid>" -extensionName "<extensionid>"

.NOTES
    Ensure you have the necessary permissions in Azure DevOps to access the extension data.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PersonalAccessToken,

    [Parameter(Mandatory=$true)]
    [string]$Organization,

    [Parameter(Mandatory=$true)]
    [string]$OutputFilePath,

    [Parameter(Mandatory=$false)]
    [string]$CollectionName = "%24settings",

    [Parameter(Mandatory=$true)]
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

# Make the GET request to download the document
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers

    # Convert the response to JSON string and save to file
    $jsonString = $response | ConvertTo-Json -Depth 10
    $jsonString | Out-File -FilePath $OutputFilePath -Encoding UTF8

    Write-Host "Successfully downloaded JSON data from Azure DevOps datastore."
    Write-Host "Document ID: $($response.id)"
    Write-Host "ETag: $($response.__etag)"
    Write-Host "Data saved to: $OutputFilePath"
} catch {
    Write-Error "Failed to download data: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd()
        Write-Error "Response body: $responseBody"
    }
    exit 1
}