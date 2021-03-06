##Setting connect to a local domain

#The script processes users in the local group Azure_MFA_Users in each domain in turn
[PSCustomObject[]]$global:domains = @()
$global:domains += [PSCustomObject]@{
PSTypeName = 'Config.Domain' #do not change
domainName = 'DOMAINNAME'
groupName = 'AAAC_Azure_MFA_Users'
foreignDomainName = '' #if not, then skip it
}
#$global:domains += [PSCustomObject]@{
#PSTypeName = 'Config.Domain'
#domainName = 'domainSecondary.local'
#groupName = 'AAAC_Azure_MFA_Users'
#foreignDomainName = 'domainPrimary.local'
#}

##Setting connect to a cloud domain

#For Azure AD, using the new module Microsoft.Graph (working in the application mode with delegated rights - UserAuthenticationMethod.ReadWrite.All)
[string]$global:AzureTenantId = "00000000-0000-0000-0000-000000000000"
[string]$global:AzureApplicationId = "00000000-0000-0000-0000-000000000000"
[string]$global:ClientCertThumbprintForAzureAuth = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"

#For AzureAD, using the old MSOnline module (working in user mode with the assigned role - Authentication administrator)
[string]$AzureUserName = "AAAC-user@DOMAINNAME"
[System.Security.SecureString]$AzuereSecurePassword = ConvertTo-SecureString -String 'PASSWORD' -AsPlainText -Force
$global:AzureCredentials = [System.Management.Automation.PSCredential]::new($AzureUserName, $AzuereSecurePassword)

#Methods Azure MFA
[System.Collections.Hashtable]$global:AzureSuitableMethods = @{
    Primary = "PhoneAppNotification"; #do not change
    Secondary = "TwoWayVoiceMobile"; #do not change
    Tertiary = "TwoWayVoiceOffice"; #do not change
    Quaternary = "TwoWayVoiceAlternateMobile" #do not change
}

#The directory for logging
$global:pathLog = $PSScriptRoot

Export-ModuleMember -Variable *