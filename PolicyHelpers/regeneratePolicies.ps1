#used to destroy all existing policies and recreate
#useful when pushing a new common cookbook, etc. USE WITH CARE.

Remove-Item policies\*.lock.json

$policiesToGenerate = Get-ChildItem policies\*.rb
foreach ($p in $policiesToGenerate) {
   chef install $p
   chef push prod $p
}

chef clean-policy-revisions
chef clean-policy-cookbooks
