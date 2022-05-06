# Install a collection of Azure DevOps extensions from a source organization into a target extension
# Prerequisites: azure cli (az), az devops extension, powershell

az devops extension list --organization https://dev.azure.com/<source> | ConvertFrom-Json | select extensionId,publisherId | where {$_.publisherId -ne 'ms'} | % {& az devops extension install --extension-id $_.extensionId --publisher-id $_.publisherId --organization https://dev.azure.com/<target>}
