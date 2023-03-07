## Install and import databricks module, Run below command as administrator

#Install-Module azure.databricks.cicd.tools -Scope CurrentUser
#Import-Module azure.databricks.cicd.tools

## Global variables

$AccessToken = "dapi03bd06d1400fa3b84c65626ecda45a8e-2"
$Region = "centralus"
$csvFile = ".\AADGroups.csv"


## Some SCIM functions required for Add-DatabrickUser function

function Get-SCIMURL {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Api,
        [Parameter(Mandatory=$false)][string]$id,
        [Parameter(Mandatory=$false)][hashtable]$filters = @{}
    )
    
    $Root = '/api/2.0/preview/scim/v2/'

    if ($PSBoundParameters.ContainsKey('id')){
        $uri = $Root + $Api + "/" + $id
    }
    else{
        $uri = $Root + $Api
    }

    if ($PSBoundParameters.ContainsKey('filters')){
        [System.Collections.ArrayList]$filterList = @()
        $filters.GetEnumerator()  | ForEach-Object { $filterList.Add("$($_.Name)=$($_.Value)") } | Out-Null

        $uri = $uri + "?" + ($filterList -join "&")
    }
    return $uri
}


function Add-SCIMSchema {
    [cmdletbinding()]
    param (
        [string[]]$schemas
    )
    $res = @{"schemas"=$schemas} 
    return $res
}


function Add-SCIMValueArray {
    [cmdletbinding()]
    param (
        [string]$Parent,
        [string[]]$Values
    )
    
    $ResArray = @()
    ForEach ($e in $Values) {
        $ResArray += @{"value"=$e}
    }

    return @{"$Parent"=$ResArray} 
}

function GetHeaders($Params){

        If ($null -ne $Params){
            If ($Params.ContainsKey('BearerToken')) {
                $BearerToken = $Params['BearerToken']
            }
            else {
                $BearerToken = $null
            }

            If ($Params.ContainsKey('Region')) {
                $Region = $Params['Region']
            }
            else {
                $Region = $null
            }

            if ($BearerToken -and $Region){
                Connect-Databricks -BearerToken $BearerToken -Region $Region | Out-Null
            }
            elseif ((DatabricksTokenState) -ne "Valid"){
                Throw "You are not connected - please execute Connect-Databricks"
            }
        }

        return $global:Headers
    }


## Add Databricks user function

Function Add-DatabrickUser
{
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$false)][string]$BearerToken,
        [parameter(Mandatory=$false)][string]$Region,
        [parameter(Mandatory=$true)][string]$Username,
        [parameter(Mandatory=$false)][string[]]$Entitlements,
        [parameter(Mandatory=$false)][string[]]$Groups
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    $Headers = GetHeaders $PSBoundParameters
    
    $uri = "$global:DatabricksURI" + (Get-SCIMURL "Users")
    $schemaR = Add-SCIMSchema "urn:ietf:params:scim:schemas:core:2.0:User"
    $entitlementsR = (Add-SCIMValueArray "entitlements" $Entitlements)
    $groupsR = (Add-SCIMValueArray "groups" $Groups)
    $usernameR = @{"userName"=$Username}

    $Body = ($schemaR + $EntitlementsR+ $usernameR + $groupsR) | ConvertTo-Json -Depth 10 

    Try {
        $Request = Invoke-RestMethod -Method Post -Body $Body -Uri $uri -Headers $Headers -ContentType "application/scim+json"
    }
    Catch {
        if ($_.Exception.Response -eq $null) {
            throw $_.Exception.Message
        } else {
            if ($_.Exception.Response.StatusCode.value__ -eq 409){
                Write-Warning "User exists - entitlements and groups may differ to requested"
            }
            else {
                throw $_.ErrorDetails.Message
            }    
        }  
    }

    return $Request
}

# read users from csv file

$csv = Import-Csv -Path $csvFile

$AADGroupsUsersList = @()

For ($i=0; $i -lt $csv.Count; $i++){
   
     Write-Host "Syncing members for AAD Group: " $csv.AADGroups[$i] -ForegroundColor Cyan
     $members = Get-AzADGroup -DisplayName $csv.AADGroups[$i] | Get-AzADGroupMember 
    

     For ($j=0; $j -lt $members.Count; $j++){

         # $x = Get-AzADUser -DisplayName $members[$j].DisplayName

         #Write-Host "Adding user to databricks: " $x.Mail -ForegroundColor Cyan
         #Add-DatabricksUser -BearerToken $AccessToken -Region $Region -Username $x.Mail
         $AADGroupsUsersList += $members[$j].UserPrincipalName
         Write-Host "Adding user to databricks: " $members[$j].UserPrincipalName -ForegroundColor Cyan
         Add-DatabrickUser -BearerToken $BearerToken -Region $Region -Username $members[$j].UserPrincipalName
    }

}

Write-Host "Finished Adding AAD Groups users to Databricks Workspace " $WorkSpaceName -ForegroundColor Cyan

## Comparing data bricks users with AAD groups users. Delete databrick user if it doesn't exist in AAD groups.

$accountdAmins = Get-AzRoleAssignment -Scope /subscriptions/$subId -IncludeClassicAdministrators -RoleDefinitionName "AccountAdministrator" | Select-Object Displayname
$accountAdminsArray = @()

$databricksUsers = Invoke-DatabricksAPI -BearerToken $BearerToken -Region $Region -API "api/2.0/preview/scim/v2/Users" -Method GET

#$AADGroupsUsersList =  $members = Get-AzADGroup -DisplayName $csv.AADGroups[$i] | Get-AzADGroupMember | Select-Object UserPrincipalName

#Get-AzADUser | Select-Object UserPrincipalName



$databricksUsersList = $databricksUsers.Resources | Select-Object username,id

## create arrays for AAD users and Account admins
#$AADUsersArray =  @()

#Foreach ($aad in $AADUsersList) {

#      $AADUsersArray += $aad.UserPrincipalName
#}

Foreach ($admin in $accountdAmins) {

      $accountAdminsArray += $accountdAmins.DisplayName
}

# Let's compare data bricks users with azure AD users and delete which don't match to AAD users.
# We won't try to delete account admins otherwise it will throw error

foreach ($user in  $databricksUsersList) { 
  

    if ($AADGroupsUsersList -notcontains $user.userName) {
     
        if ($accountAdminsArray -contains $user.userName ){

           write-host $user.userName " is an account admin, skip this one"
        }
        else {
              write-host $user.userName "Doesn't exist in AAD, let's delete this user"
              write-host "Deleting user from databricks: " $user.userName 

              Try {

                  $id = $user.id
                  Invoke-DatabricksAPI -BearerToken $AccessToken -Region $Region -API "api/2.0/preview/scim/v2/Users/$id" -Method DELETE
              }
              Catch {
                  if ($_.Exception.Response -eq $null) {
                     throw $_.Exception.Message
                  } 
                  else {
                     if ($_.Exception.Response.StatusCode.value__ -eq 409){
                        Write-Warning "Can't delete user"
                     }
                     else {
                        throw $_.ErrorDetails.Message
                    }    
                 }  
              }

          }
    } 
    else {
        write-host $user.userName " : is now syncronized with Azure AD" -ForegroundColor green
    }
}

