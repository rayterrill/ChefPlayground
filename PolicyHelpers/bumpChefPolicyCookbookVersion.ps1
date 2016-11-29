#used to bump the cookbook version for a set of policies (or all policies)
#useful when moving all nodes to a new version of a common cookbook
#usage: ./bumpChefPolicyCookbookVersion.ps1 -resourceToReplace 'cookbook "SQLServer", "= 0.1.3"' -newResource 'cookbook "SQLServer", "= 0.1.4"'

param (
   [Parameter(Mandatory=$true)][string]$resourceToReplace,
   [Parameter(Mandatory=$true)][string]$newResource
)

$policies = Get-ChildItem ./policies/*.rb

foreach ($p in $policies) {
   (Get-Content $p).replace("$resourceToReplace", "$newResource") | Set-Content $p
}
