#This code/program was created and belongs to _KUL
#Distributed under Apache License 2.0

import-module Microsoft.Graph.Identity.SignIns
import-module MSOnline
Import-Module ("$PSScriptRoot\EnvConf.psm1")

#Global counter log
$global:couners = [myCounters]::new()

class myCounters
{
    [int]$ConnectionError
    [int]$ADUserNotFoundInAAD
    [int]$ADUserNoMfaAndNoMobile
    [int]$MfaMethodPhoneAddedUsers
    [int]$ErrorMfaMethodPhoneAddedUsers
    [int]$ChangeDefaultMethodMfaUsers
    [int]$ErrorChangeDefaultMethodMfaUsers
    [int]$ProcessingTimeSecond
    [string]$CollectionTime

    Reset()
    {
        $this.ConnectionError = 0
        $this.ADUserNotFoundInAAD = 0
        $this.ADUserNoMfaAndNoMobile = 0
        $this.MfaMethodPhoneAddedUsers = 0
        $this.ErrorMfaMethodPhoneAddedUsers = 0
        $this.ChangeDefaultMethodMfaUsers = 0
        $this.ErrorChangeDefaultMethodMfaUsers = 0
        $this.ProcessingTimeSecond = 0
        $this.CollectionTime = ""
    }
    Write()
    {
        $str = "ConnectionError=$($this.ConnectionError)`r`n"+
        "ADUserNotFoundInAAD=$($this.ADUserNotFoundInAAD)`r`n"+
        "ADUserNoMfaAndNoMobile=$($this.ADUserNoMfaAndNoMobile)`r`n"+
        "MfaMethodPhoneAddedUsers=$($this.MfaMethodPhoneAddedUsers)`r`n"+
        "ErrorMfaMethodPhoneAddedUsers=$($this.ErrorMfaMethodPhoneAddedUsers)`r`n"+
        "ChangeDefaultMethodMfaUsers=$($this.ChangeDefaultMethodMfaUsers)`r`n"+
        "ErrorChangeDefaultMethodMfaUsers=$($this.ErrorChangeDefaultMethodMfaUsers)`r`n"+
        "ProcessingTimeSecond=$($this.ProcessingTimeSecond)`r`n"+
        "CollectionTime=$($this.CollectionTime)"
        Out-File -InputObject $str -FilePath "$($global:pathLog)\counters.txt" -Encoding "unicode"
    }
}

enum LogLevelMsg
{
	Info = 1
	Warning = 2
}


#General-purpose functions
function Add-ToLog([LogLevelMsg]$Level, [string]$msg)
{
    if (!$Level -or !$msg) {return}
    $str = "$(Get-date -Format u) | $($Level.ToString()) | $msg"
    Out-File -InputObject $str -FilePath "$($global:pathLog)\log.txt" -Append -Encoding "unicode"
}
function Backup-Log()
{
    $log = Get-Item "$($global:pathLog)\log.txt" -ErrorAction SilentlyContinue
    if (!$log -or $log.Length -lt 304087040) {return}
    if (Test-Path "$($global:pathLog)\log.txt.veryold") {Remove-Item "$($global:pathLog)\log.txt.veryold"}
    if (Test-Path "$($global:pathLog)\log.txt.old") {Move-Item "$($global:pathLog)\log.txt.old" "$($global:pathLog)\log.txt.veryold"}
    Move-Item "$($global:pathLog)\log.txt" "$($global:pathLog)\log.txt.old"
}
function Remove-Log()
{
    if (Test-Path "$($global:pathLog)\log.txt.veryold") {Remove-Item "$($global:pathLog)\log.txt.veryold"}
    if (Test-Path "$($global:pathLog)\log.txt.old") {Remove-Item "$($global:pathLog)\log.txt.old"}
    if (Test-Path "$($global:pathLog)\log.txt") {Remove-Item "$($global:pathLog)\log.txt"}
}

#Functions for Azure AD
function Connect-NewAPI([string]$AzureTenantId, [string]$AzureApplicationId, [string]$ClientCertThumbprintForAzureAuth)
{
    try 
    {
        $null = Connect-MgGraph -TenantId $AzureTenantId -ClientId $AzureApplicationId -CertificateThumbprint $ClientCertThumbprintForAzureAuth
        Select-MgProfile -Name beta
    }
    catch 
    {
        return [bool]$false
    }
    return [bool]$true
}
function Connect-OldAPI([System.Management.Automation.PSCredential]$AzureCredentials)
{
    try 
    {
        $null = Connect-MsolService -Credential $AzureCredentials
    }
    catch 
    {
        return [bool]$false
    }
    return [bool]$true
}
function Find-SuitableAuthMethod([Microsoft.Online.Administration.User]$MOAUUser, [System.Collections.Hashtable]$AzureSuitableMethods)
{
    [bool]$found = $false
    foreach ($methodOfAuth in $MOAUUser.StrongAuthenticationMethods) 
    {
        if ($AzureSuitableMethods.ContainsValue($methodOfAuth.MethodType)) {$found = $true}
    }
    return [bool]$found
}
function Assert-SuitableAuthMethodIsSelected([Microsoft.Online.Administration.User]$MOAUUser, [System.Collections.Hashtable]$AzureSuitableMethods)
{
    [bool]$isSelected = $false
    foreach ($methodOfAuth in $MOAUUser.StrongAuthenticationMethods) 
    {
        if ($AzureSuitableMethods.ContainsValue($methodOfAuth.MethodType) -and $methodOfAuth.IsDefault) {$isSelected = $true}
    }
    return [bool]$isSelected
}
function Get-IsTheAdministrator([string]$UPN)
{
    $MOAUUser = Get-MsolUserRole -UserPrincipalName $UPN
    $measure = $MOAUUser.name | Where-Object {$_ -match "administrator"} | Measure-Object
    if ($measure.Count -gt 0)
    {
        return [bool]$true
    }
    else
    {
        return [bool]$false
    }
}
function Add-MFAMethod-Mobile([string]$UPN, [string]$Phone)
{
    $null = New-MgUserAuthenticationPhoneMethod -UserId $UPN -PhoneType "mobile" -PhoneNumber $Phone -ErrorVariable addMFAErr -ErrorAction SilentlyContinue
    if ($addMFAErr.Count -eq 0)
    {
        return [bool]$true
    }
    else
    {
        return [bool]$false
    }
}
function Update-DefaultOfSuitableAuthMethod([string]$UPN, [Microsoft.Online.Administration.User]$MOAUUser, [System.Collections.Hashtable]$AzureSuitableMethods)
{
    [bool]$defaulMethodIsSet = $false
    if (!(Find-SuitableAuthMethod -MOAUUser $MOAUUser -AzureSuitableMethods $AzureSuitableMethods)) {return $defaulMethodIsSet}

    [int]$positionPrimaryMethod = -1
    [int]$positionSecondaryMethod = -1
    [int]$positionTertiaryMethod = -1

    for ([int]$itemOfMethodsAuth = 0; $itemOfMethodsAuth -lt $MOAUUser.StrongAuthenticationMethods.Count; $itemOfMethodsAuth++) 
    {
        if ($MOAUUser.StrongAuthenticationMethods[$itemOfMethodsAuth].IsDefault) {$MOAUUser.StrongAuthenticationMethods[$itemOfMethodsAuth].IsDefault = $false}
        
        if ($MOAUUser.StrongAuthenticationMethods[$itemOfMethodsAuth].MethodType -eq $AzureSuitableMethods.Primary) {$positionPrimaryMethod = $itemOfMethodsAuth}
        if ($MOAUUser.StrongAuthenticationMethods[$itemOfMethodsAuth].MethodType -eq $AzureSuitableMethods.Secondary) {$positionSecondaryMethod = $itemOfMethodsAuth}
        if ($MOAUUser.StrongAuthenticationMethods[$itemOfMethodsAuth].MethodType -eq $AzureSuitableMethods.Tertiary) {$positionTertiaryMethod = $itemOfMethodsAuth}
    }

    if ($positionPrimaryMethod -ge 0)
    {
        $MOAUUser.StrongAuthenticationMethods[$positionPrimaryMethod].IsDefault = $true
        $defaulMethodIsSet = $true
    }
    if ($positionPrimaryMethod -lt 0 -and $positionSecondaryMethod -ge 0)
    {
        $MOAUUser.StrongAuthenticationMethods[$positionSecondaryMethod].IsDefault = $true
        $defaulMethodIsSet = $true
    }
    if ($positionPrimaryMethod -lt 0 -and $positionSecondaryMethod -lt 0 -and $positionTertiaryMethod -ge 0)
    {
        $MOAUUser.StrongAuthenticationMethods[$positionTertiaryMethod].IsDefault = $true
        $defaulMethodIsSet = $true
    }

    if ($defaulMethodIsSet)
    {
        $null = Set-MsolUser -UserPrincipalName $UPN -StrongAuthenticationMethods @($($MOAUUser.StrongAuthenticationMethods)) -ErrorVariable changeError -ErrorAction SilentlyContinue
        if ($changeError.Count -ne 0) {$defaulMethodIsSet = $false}
    }

    return [bool]$defaulMethodIsSet
}


#Functions for Active Directory

class myADUser {
    [string]$adGuid
    [string]$adUserPrincipalName
    [string]$adMobile
    [string]$adTelephoneNumber
    [string]$formattedPhone

    myADUser([string]$adGuid, [string]$adUserPrincipalName, [string]$adMobile, [string]$adTelephoneNumber)
    {
        $this.adGuid = $adGuid
        $this.adUserPrincipalName = $adUserPrincipalName
        $this.adMobile = $adMobile
        $this.adTelephoneNumber = $adTelephoneNumber
        $this.formattedPhone = Convert-PhoneNumber -adTelephoneNumber $adTelephoneNumber -adMobile $adMobile
    }
}
#Converting the phone number to the MFA Azure format
#If necessary, you can try to get the phone from different user attributes
function Convert-PhoneNumber([string]$adTelephoneNumber, [string]$adMobile)
{
    $tmpPhone = [System.String]::new('')

    #if (!$adTelephoneNumber -and !$adMobile) {return $null}
    if (!$adMobile) {return $null}
    #if ($adTelephoneNumber) {$tmpPhone = $adTelephoneNumber}

    if ($adMobile) {$tmpPhone = $adMobile}

    $tmpPhone = $tmpPhone -replace "\D", ""
    $tmpPhone = $tmpPhone -replace "^8|^7", "+7 "

    if ($tmpPhone.Length -eq 13)
    {
        return [string]$tmpPhone
    }
    else
    {
        return $null
    }
}

function Get-UsersFromADGroup([PSTypeName('Config.Domain')]$currentDomain)
{
    $groupWithUsersForMFA = Get-ADGroup -Identity $currentDomain.groupName -Properties Members -Server $currentDomain.domainName
    if ($null -eq $groupWithUsersForMFA -or $groupWithUsersForMFA.Members -lt 1) {return $null}
    [myADUser[]]$listADUsers = @()
    foreach ($memberOfGroup in $groupWithUsersForMFA.Members)
    {
        $ADObject = Get-ADObject -Identity $memberOfGroup -Properties cn,ObjectClass,objectSid -Server $currentDomain.domainName
        if ($ADObject.ObjectClass -eq "user")
        {
            $ADUser = $null
            $ADUser = Get-ADUser -Identity $ADObject.objectSid -Properties objectGUID,DistinguishedName,ObjectClass,mobile,telephoneNumber,userPrincipalName,Enabled -Server $currentDomain.domainName
            if (!$ADUser.Enabled) {continue}
            $listADUsers += [myADUser]::new($ADUser["objectGUID"], $ADUser["userPrincipalName"], $ADUser["mobile"], $ADUser["telephoneNumber"])
        }
        if ($ADObject.ObjectClass -eq "foreignSecurityPrincipal")
        {
            $ADUser = $null
            $ADUser = Get-ADUser -Identity $ADObject.objectSid -Properties objectGUID,DistinguishedName,ObjectClass,mobile,telephoneNumber,userPrincipalName,Enabled -Server $currentDomain.foreignDomainName
            if (!$ADUser.Enabled) {continue}
            $listADUsers += [myADUser]::new($ADUser["objectGUID"], $ADUser.userPrincipalName, $ADUser["mobile"], $ADUser["telephoneNumber"])
        }
        if ($ADObject.ObjectClass -eq "group")
        {
            $tmpDomains = [PSCustomObject]@{
                PSTypeName = 'Config.Domain'
                domainName = $currentDomain.domainName
                groupName = $ADObject["CN"].Value
                foreignDomainName = $currentDomain.foreignDomainName
            }
            $tmpList = Get-UsersFromADGroup -currentDomain $tmpDomains
            $listADUsers += $tmpList
        }
    }
    return [myADUser[]]$listADUsers
}

function Read-Domain()
{
    Backup-Log
    foreach ($currentDomain in $global:domains) {
        $resultConnectNewApi = Connect-NewAPI -AzureTenantId $global:AzureTenantId -AzureApplicationId $global:AzureApplicationId -ClientCertThumbprintForAzureAuth $global:ClientCertThumbprintForAzureAuth
        $resultConnectOldApi = Connect-OldAPI -AzureCredentials $global:AzureCredentials
        if (!$resultConnectNewApi -and $resultConnectOldApi)
        {
            $global:couners.ConnectionError++
            Add-ToLog -level Warning -msg "Connection error to Azure AD"
            return
        }

        [myADUser[]]$listMyADUser = Get-UsersFromADGroup -currentDomain $currentDomain
        foreach ($myADuser in $listMyADUser) {
            $MOAUUser = $null
            $MOAUUser = Get-MsolUser -UserPrincipalName $myADuser.adUserPrincipalName -ErrorAction SilentlyContinue
            if (!$MOAUUser) 
            {
                $global:couners.ADUserNotFoundInAAD++
                Add-ToLog -level Warning -msg "User $($myADuser.adUserPrincipalName) not found in AAD"
                continue
            }
            if ((Get-IsTheAdministrator -UPN $myADuser.adUserPrincipalName)) {continue}
            if (!(Find-SuitableAuthMethod -MOAUUser $MOAUUser -AzureSuitableMethods $global:AzureSuitableMethods)) 
            {
                if ($myADuser.formattedPhone)
                {
                    $resAddMFA = Add-MFAMethod-Mobile -UPN $myADuser.adUserPrincipalName -Phone $myADuser.formattedPhone
                    if ($resAddMFA) 
                    {
                        $global:couners.MfaMethodPhoneAddedUsers++
                        Add-ToLog -level Info -msg "Added MFA method Phone $($myADuser.formattedPhone) for user $($myADuser.adUserPrincipalName)"
                        
                    }
                    else
                    {
                        $global:couners.ErrorMfaMethodPhoneAddedUsers++
                        Add-ToLog -level Warning -msg "Error adding the MFA method Phone $($myADuser.formattedPhone) for user $($myADuser.adUserPrincipalName)"
                    }
                    #Azure AD will fix the new method in 10 seconds, in order not to wait, we will make an adjustment of the methods to the user in the next pass. 
                    #If there was a one-time launch, then be sure to run it again in a minute.
                    continue
                }
                else 
                {
                    $global:couners.ADUserNoMfaAndNoMobile++
                    Add-ToLog -level Info -msg "The user $($myADuser.adUserPrincipalName) does not have MFA methods and does not have a mobile number in AD"
                    continue
                }
            }
            if (!(Assert-SuitableAuthMethodIsSelected -MOAUUser $MOAUUser -AzureSuitableMethods $global:AzureSuitableMethods)) 
            {
                $resUpdateMFA = Update-DefaultOfSuitableAuthMethod -UPN $myADuser.adUserPrincipalName -MOAUUser $MOAUUser -AzureSuitableMethods $global:AzureSuitableMethods
                if ($resUpdateMFA)
                {
                    $global:couners.ChangeDefaultMethodMfaUsers++
                    Add-ToLog -level Info -msg "Changed the default MFA method for the user $($myADuser.adUserPrincipalName)"
                }
                else
                {
                    $global:couners.ErrorChangeDefaultMethodMfaUsers++
                    Add-ToLog -level Warning -msg "Error changing the default MFA method for the user $($myADuser.adUserPrincipalName)"
                }
            }
        }
    }
}

function Start-Work([Parameter(Mandatory=$true)][bool]$Recursive)
{
    do
    {
        if (!$Recursive) {Remove-Log}
        $global:couners.Reset()
        $startTime = Get-Date
        Read-Domain
        $endTime = Get-Date
        $global:couners.ProcessingTimeSecond = (New-TimeSpan -start $startTime -end $endTime).TotalSeconds
        $global:couners.CollectionTime = $endTime.GetDateTimeFormats('u')
        $global:couners.Write()
        Start-Sleep -Seconds 60
    }
    while ($Recursive)
}

Start-Work -Recursive $false