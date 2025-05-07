# Install a collection of Azure DevOps extensions from onpremise AzD server (source) into a Azure DevOps service (target) cloud orga
# Prerequisites: azure cli (az), az devops extension, powershell
# Install Azure DevOps CLI: https://docs.microsoft.com/en-us/azure/devops/cli/?view=azure-devops

#  1. Retrieve extension list via Database SQL Query:
      SELECT
      [PublisherName]
      ,[ExtensionName]
      FROM [<CollectionDBName>].[Extension].[tbl_InstalledExtension]
      where not PublisherName = 'ms'
#  2. Save query output as CSV file and add header "PublisherName;ExtensionName" to that file 
#  3. Install Extensions using Azure CLI
      az login
      az devops login
      Import-Csv .\Extensions.csv -Delimiter ";" | where {$_.publisherId -ne 'ms'} | % {& az devops extension install --extension-id $_.ExtensionName --publisher-id $_.PublisherName --organization https://dev.azure.com/<target>}
