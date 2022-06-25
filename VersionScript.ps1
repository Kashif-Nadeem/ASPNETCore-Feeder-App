
$folderPath = "C:\inetpub\wwwroot"
$webConfig   = "web.config"
$appSettings = "appsettings.json"

$webConfigLine = "`n<!---version = 2022.6.24.xx--->"  ## `r required to add string to new line

$appSettingsLine = "`n//version = 2022.6.24.xx//"

$items = Get-ChildItem -Path $folderPath   

Get-ChildItem -Path $folderPath -

for ($i=0 ; $i -lt $items.Count; $i++){

  #Write-Host "File name: " $items[$i]

  if ($items[$i].Name -eq $webConfig){

    Write-Host "web.config found: " $items[$i].FullName

    $temp = ".\temp.txt"

    Get-Content $items[$i].FullName | Where-Object {$_ -notmatch 'version'} | Set-Content $temp

    Get-Content $temp | Set-Content $items[$i].FullName

    Add-Content $items[$i].FullName $webConfigLine

    (gc $items[$i].FullName) | ? {$_.trim() -ne "" } | set-content $items[$i].FullName

    Remove-Item -Path $temp
  }

  elseif ($items[$i].Name -eq $appSettings) {

    Write-Host "appsettings.json found: " $items[$i].FullName

    $temp1 = ".\temp1.txt"

    Get-Content $items[$i].FullName | Where-Object {$_ -notmatch 'version'} | Set-Content $temp1

    Get-Content $temp1 | Set-Content $items[$i].FullName

    Add-Content $items[$i].FullName $appSettingsLine 

    (gc $items[$i].FullName) | ? {$_.trim() -ne "" } | set-content $items[$i].FullName

    Remove-Item -Path $temp1
 
  }

}