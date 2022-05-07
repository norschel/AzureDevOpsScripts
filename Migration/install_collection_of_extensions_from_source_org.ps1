# Install a collection of Azure DevOps extensions from a source organization into a target extension
# Prerequisites: azure cli (az), az devops extension, powershell
# Install Azure DevOps CLI: https://docs.microsoft.com/en-us/azure/devops/cli/?view=azure-devops

az devops extension list --organization https://dev.azure.com/<source> | ConvertFrom-Json | select extensionId,publisherId | where {$_.publisherId -ne 'ms'} | % {& az devops extension install --extension-id $_.extensionId --publisher-id $_.publisherId --organization https://dev.azure.com/<target>}
