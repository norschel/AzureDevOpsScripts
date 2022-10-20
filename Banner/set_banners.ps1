# Use case: create Azure DevOps notification banners using Powershell, REST API and JSON files.
# The script is searching for files with the name schema banners*.json which must be located in the current working directory.
# Each json files contains one banner (message, loglevel, expire date).

# To start the script you need the collection / org url and a PAT.
# The PAT must be encoded as a secure string.
# e.g. In Powershell 7 you can create a secure string with "$pat = read-host -AsSecureString"

# Format of json files
#{
#    "Message": "<string>",
#    "Level":"Error/Warning/Info",
#    "ExpirationDate":"2022-10-23T14:48:00.000Z",
#    "Prio":"p0/p1/p2"  
#} 

# Inspired by https://github.com/microsoft/banner-settings-ado-extension


[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$collectionUrl,
    [Parameter(Mandatory=$true)]
    [SecureString]$pat)

#Auth against AzD service or server
$patPlain = ConvertFrom-SecureString $pat -AsPlainText;

$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("PAT:$($patPlain)"))
$basicAuthValue = "Basic $encodedCreds"

$Headers = @{
    Authorization = $basicAuthValue
}

$bannerFileNames = Get-ChildItem -Filter banner*.json
if ($bannerFileNames.Count -eq 0) {
    write-host "Found no banner files"
    exit 100
}
else {
    Write-Host "Found $($bannerFileNames.Count) banner files." -ForegroundColor Blue
}

#retrieve all existing banners
$apiUri = "{0}/_apis/settings/entries/host/GlobalMessageBanners?api-version=6.0-preview" -f $collectionUrl

$response = Invoke-WebRequest -Uri $apiUri -Headers $Headers

if ($response.StatusCode -eq 200) {
    $content = $response.Content | ConvertFrom-Json
    $messageIds = [System.Collections.Generic.List[string]]::new()
    $content.value | get-member | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object { $messageIDs.Add($_) }
    write-host "New banners:" -ForegroundColor Green
    $json = ($response.Content | ConvertFrom-Json).value
    ForEach ($banner in $json.PSObject.Properties) {
        Write-Host ("{0} : {1} : {2}" -f $banner.Value.message, $banner.Value.Level, $banner.Value.ExpirationDate)
    }
}

# Delete all existing banners
$response = Invoke-WebRequest -Uri $apiUri -Headers $Headers -Method Delete
write-host "Deleted all existing banners" -ForegroundColor Yellow

# add new banner
$apiUri = "{0}/_apis/settings/entries/host?api-version=6.0-preview" -f $collectionUrl

#Sample
#{"GlobalMessageBanners/p2-1666102239075":{"level":"Info","message":"rest"}}

$firstFile = $true;
$bannerEntries = "{";

foreach ($filename in $bannerFileNames) {
    [string]$banner = Get-Content $filename
    [psobject]$banner = ConvertFrom-Json -InputObject $banner

    $priority = $banner.Prio #p0, p1, p2
    $level = $banner.Level; #Warning, Info, Error
    $message = $banner.Message
    $expirationDate = $banner.ExpirationDate; #e.g. 2011-10-05T14:48:00.000Z

    $date = get-date
    $pattern = "MM/dd/yyyy H:mm:ss"
    if ([DateTime]::ParseExact($expirationDate,$pattern,$null) -gt $date) {

        [string] $messageID = Get-Date | Select-Object Ticks -ExpandProperty Ticks
        $messageID += get-random -Maximum 1000
        $title = "GlobalMessageBanners/$priority-$messageID";

        $entry = """$title"":{
        ""message"": ""$message"",
        ""level"": ""$level"",
        ""expirationDate"": ""$expirationDate""
    }"

        if (!$firstFile) {
            $entry = ",$entry"  
        }
        else {
            $firstFile = $false;
        }
        $bannerEntries += $entry;
    }
    else {
            write-host "Skipping banner file because expiration date is in the past"
    }
}

$bannerEntries += "}";

$response = Invoke-WebRequest -Uri $apiUri -Headers $Headers -Method Patch -Body $bannerEntries -ContentType "application/json"
Write-Host "Adding new banners was successful" -ForegroundColor Yellow
#$addResponse

#retrieve all existing banners
$apiUri = "{0}/_apis/settings/entries/host/GlobalMessageBanners?api-version=6.0-preview" -f $collectionUrl

$response = $null
$content = $null
$messageIDs = $null

$response = Invoke-WebRequest -Uri $apiUri -Headers $Headers -Method Get

if ($response.StatusCode -eq 200) {
    $content = $response.Content | ConvertFrom-Json
    $messageIds = [System.Collections.Generic.List[string]]::new()
    $content.value | get-member | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object { $messageIDs.Add($_) }
    write-host "New banners:" -ForegroundColor Green
    $json = ($response.Content | ConvertFrom-Json).value
    ForEach ($banner in $json.PSObject.Properties) {
        Write-Host ("{0} : {1} : {2}" -f $banner.Value.message, $banner.Value.Level, $banner.Value.ExpirationDate)
    }
}