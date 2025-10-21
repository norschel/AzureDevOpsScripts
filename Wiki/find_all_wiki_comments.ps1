<#
.SYNOPSIS
    Finds and counts all comments in Azure DevOps wiki pages across all projects.

.DESCRIPTION
    This script connects to an Azure DevOps organization or server using a Personal Access Token (PAT)
    and retrieves all wiki pages from all projects. It then counts the comments on each page
    and provides a summary of comment counts per wiki and per project.

.PARAMETER CollectionUrl
    The URL of the Azure DevOps organization or server collection (e.g., https://dev.azure.com/yourorg).

.PARAMETER Pat
    A Personal Access Token with appropriate permissions to read wikis and comments.

.PARAMETER ProjectFilter
    Optional array of project names to filter the search. If empty, all projects are processed.

.EXAMPLE
    .\find_all_wiki_comments.ps1 -CollectionUrl "https://dev.azure.com/yourorg" -Pat "yourpat"

.EXAMPLE
    .\find_all_wiki_comments.ps1 -CollectionUrl "https://dev.azure.com/yourorg" -Pat "yourpat" -ProjectFilter @("ProjectA", "ProjectB")

.NOTES
    Requires PowerShell and internet access to Azure DevOps.
    Adjust API versions for Azure DevOps Server compatibility.
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$CollectionUrl,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$Pat,

  [Parameter(Mandatory = $false)]
  [string[]]$ProjectFilter = @()
)

# Adjust for Azure DevOps Server depending on version:
# Server 2019/2020 => 5.0/5.1; Server 2022 => 7.0
$ApiCore         = "7.0"              # Projects
$ApiWiki         = "7.0"              # Wikis/Pages

# ===== Helper =====
$AuthHeader = @{
  Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
}

$VerbosePreference = "Continue"

function Invoke-DevOpsGet {
  param([string]$Uri)
  write-Verbose "Invoking GET $Uri"
  Invoke-RestMethod -Method GET -Uri $Uri -Headers $AuthHeader -ErrorAction Stop
}

# Find ID for wiki page url
function Get-WikiPageId {
    param (
        [string]$pageUrl
    )

    Write-Verbose "Getting Wiki Page ID for path: $PagePath"

    # Normalize pageUrl to pages?path=/... form for the pages API
    if ($pageUrl -match '/pages\?') {
        $uri = $pageUrl
    } elseif ($pageUrl -match '/pages/') {
        $parts = $pageUrl -split '/pages/'
        $prefix = $parts[0]
        $pagePart = $parts[1] -split '[\?#]' | Select-Object -First 1
        $decoded = [uri]::UnescapeDataString($pagePart)
        if ($decoded -notmatch '^/') { $decoded = '/' + $decoded }
        $uri = "$prefix/pages?path=$([uri]::EscapeDataString($decoded))&api-version=$ApiWiki"
    } else {
        $uri = $pageUrl
    }
    $resp = Invoke-DevOpsGet -Uri $uri
    Write-Verbose "Found Wiki Page ID: $($resp.id) for URL: $pageUrl"
    
    if (-not $resp.id) {
        write-Verbose "Could not find Wiki Page ID for URL: $pageUrl, returning null"
        return $null
    }
    return $resp.id
}



# Pagination for comments
function Get-WikiPageCommentCount {
  param(
    [string]$Project,
    [string]$WikiIdOrName,
    [string]$PageUrl
  )
  Write-Verbose "Counting comments for Page URL $PageUrl in Wiki '$WikiIdOrName' of Project '$Project'..."
  $wikiPageId = Get-WikiPageId -pageUrl $PageUrl
  $PageUrl = $PageUrl -replace '/[^/]*$',''
  $PageUrl = $PageUrl.TrimEnd('/')

  # this API is not part of the official REST API documentation on MS Learn (unofficial)
  $base = "$pageUrl/$($wikiPageId)/comments?%24top=1000&excludeDeleted=true&%24expand=9"

  $count = 0
  $ct = $null
  do {
    write-Verbose "Fetching comments page with continuationToken='$ct'..."
    $uri = if ($ct) { "$base&continuationToken=$([uri]::EscapeDataString($ct))" } else { $base }
    if ($null -eq $wikiPageId) {
        write-Verbose "Wiki Page ID is null, returning 0 comments."
        return 0
    }
    $resp = Invoke-DevOpsGet -Uri $uri
    if ($resp.comments) { $count += $resp.comments.Count }
    $ct = $resp.continuationToken
  } while ($ct)
  return $count
}

# Recursively collect all page IDs (via recursionLevel=full)
function Get-AllWikiPageIds {
  param(
    [string]$Project,
    [string]$WikiIdOrName
  )

  Write-Verbose "Collecting pages for Wiki '$WikiIdOrName' in Project '$Project'..."
  $root = "$CollectionUrl/$Project/_apis/wiki/wikis/$WikiIdOrName/pages?path=/&recursionLevel=full&api-version=$ApiWiki"
  $resp = Invoke-DevOpsGet -Uri $root
  # The API provides a tree structure; IDs are in subpages/individual pages
  $ids = New-Object System.Collections.Generic.List[string]
  Write-Verbose "Root page Response: $($resp)"
  write-Verbose "Traversing page tree..."
  
  function Collect($node) {
    Write-Verbose "Visiting node: $($node.path) with Url: $($node.url)"
    if ($null -ne $node.url) { $ids.Add($node.url) }
    if ($node.subPages) { $node.subPages | ForEach-Object { Collect $_ } }
  }
  Collect $resp
  return $ids
}

# ===== Main run =====
# Fetch projects
Write-Verbose "Fetching projects..."
$projUri = "$CollectionUrl/_apis/projects?stateFilter=all&$top=1000&api-version=$ApiCore"
$projects = (Invoke-DevOpsGet -Uri $projUri).value
write-Verbose "Found $($projects.Count) projects."

if ($ProjectFilter.Count -gt 0) {
  $projects = $projects | Where-Object { $ProjectFilter -contains $_.name }
}

$result = @()

foreach ($p in $projects) {
  $projName = $p.name

  Write-Verbose "Processing Project: $projName"
  $wikisUri = "$CollectionUrl/$projName/_apis/wiki/wikis?api-version=$ApiWiki"
  $wikis = (Invoke-DevOpsGet -Uri $wikisUri).value

  $projTotal = 0
  foreach ($wiki in $wikis) {
    $wikiIdOrName = if ($wiki.id) { $wiki.id } else { $wiki.name }
    $pageIds = Get-AllWikiPageIds -Project $projName -WikiIdOrName $wikiIdOrName

    $wikiCount = 0
    foreach ($pageUrl in $pageIds) {
      $wikiCount += Get-WikiPageCommentCount -Project $projName -WikiIdOrName $wikiIdOrName -PageUrl $pageUrl
    }

    $projTotal += $wikiCount
    $result += [pscustomobject]@{
      Project       = $projName
      Wiki          = $wiki.name
      CommentsCount = $wikiCount
    }
  }
}

# Output: summarized per project + detail per wiki
$byProject = $result | Group-Object Project | ForEach-Object {
  [pscustomobject]@{
    Project       = $_.Name
    CommentsTotal = ($_.Group | Measure-Object -Property CommentsCount -Sum).Sum
  }
}

"=== Comments per project ==="
$byProject | Sort-Object CommentsTotal -Descending | Format-Table -AutoSize

"`n=== Details per wiki ==="
$result | Sort-Object Project, CommentsCount -Descending | Format-Table -AutoSize