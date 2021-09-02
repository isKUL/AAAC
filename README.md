# artemius-azure-authentication-corrector
## Description
* The main purpose of the system system is to maintain user correctly working when using Remote Desktop Service (RDS) with Azure Multi-Factor Authentication (MFA), so the system automatically sets the optimal authentication methods (Microsoft Authenticator or Phone number) for working through the Remote Desktop Protocol (RDP) from the user's added ones. 
* Additionally, this system is designed to process corporate users and automatically add a phone number from local Active Directory for authentication methods of Azure Active Directory when further using the Azure Multi-Factor Authentication (MFA) system. 

## Required environment
1. Local Active Directory Domain (`AD`).
2. Registered Tenant in Azure Active Directory (`AAD`) with an Azure AD Premium P2 license.
3. Configured hybrid synchronization of users from AD to AAD.

## Work architecture
1. Processing specified domains.
2. In AD, the specified group is searched for processing. The group must be filled with active users or a group with active users.
3. By the user from AD is searched in AAD by userPrincipalName.
4. If the user has administrative roles in AAD, then we ignore the processing. For GraphAPI, we specifically assign weak rights. Administrators are strong specialists, they will be able to configure authentication methods for themselves.
5. We check with the user in AAD whether there are correct methods for working through RDP.
6. If there are no methods, then we are trying to add a phone for the user to the AAD from the `mobile` attribute of the local AD
7. We check with the user in AAD which default method is installed. Is this method suitable for working via RDP.
8. If not, then we are trying to set method **Microsoft Authenticator** or method **Phone number**
9. The results of the work will be written to a file `log.txt` and the total number of processed users will be written to the file `counters.txt`

# Integration into the infrastructure

## Setting up AAD
The automation system uses 2 modules. `MSOnline` - can only use a primitive connection technology and verification by login and password. `Microsoft.Graph.Identity.SignIns` - can use the connection technology with certificate verification.
The system will work in automatic mode, on the enterprise server, so it is convenient for us to create a local user in AD to store the certificate in his profile. Thus, we have a local account that stores a certificate for authorization through Microsoft.Graph.Identity.SignIns, but the same account is subsequently synchronized with AAD and we assign a administrative role for this account to work through MSOnline.

### Creating a user for MSOnline
1. Create an `artemius-corrector-user` account in the local AD
2. Go ahead https://aad.portal.azure.com
3. In the `Roles and administrators` section, assign the `Authentication administrator` role for the synchronized artemius-corrector-user

### Creating an application for Microsoft.Graph.Identity.SignIns
The system will work in automatic mode, on the enterprise server, so it is convenient for us to create a local user in AD to store the certificate in his profile.
1. Log in to the local server on behalf of artemius-corrector-user
2. Creating a self-signed certificate `New-SelfSignedCertificate -Subject "CN=artemius-azure-authentication-corrector" -CertStoreLocation "Cert:\CurrentUser\My"  -KeyExportPolicy Exportable -KeySpec Signature -NotAfter (Get-date).AddYears(5) -KeyAlgorithm RSA -KeyLength 4096 -HashAlgorithm sha256`
3. Launch mmc.exe on behalf of the user artemius-corrector-user, we add the snap-in certificates of the current user. Exporting the public key.
4. Go ahead https://aad.portal.azure.com
5. App registrations and create the artemius-corrector application. In the `Overview section`, we remember the `Application (client) ID` and `Directory (tenant) ID`.
6. In the `Certificates & secrets` section, add the public part of our certificate and remember the `Thumbprint`.
7. In the `API permissions` section, add the permission `User Authentication Method.Read Write.All` and `User. Read.All` and click `Grant admin consent for xxx`.

## Setting up the Automation System
1. Log in to the local server and run the PowerShell console as an administrator.
2. Install the necessary modules. When the installation is complete, close the administrative console.
```
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-Module Microsoft.Graph.Identity.SignIn
Install-Module MSOnline
```
3. Copy the files to a directory on the server. Make sure that the artemius-corrector-user has access to this directory.
- artemius-azure-authentication-corrector.ps1
- EnvConf.psm1
4. Open the file `Env Conf. psm1` and the configuration variables. Attention, the file will store the password from the MSOnline module, so you need to protect access to this directory or to this server.

## Starting the system

### Manual start
Run PowerShell as artemius-corrector-user and navigate to the directory with the executable script artemius-azure-authentication-corrector.ps1 for its further launch. In the last line of the script, there is a line `Start-Work -Recursive $false` that tells you in which mode you need to perform processing. Make sure that the value is set to $false. After the first launch and its successful execution, the script must be run a second time! This is necessary so that for users who were added phone numbers from AD to AAD during the first processing, the phone numbers are set by default methods during the next processing.

### Automatic start
1. In the last line of the artemius-azure-authentication-corrector script.1 find the value of `Start-Work-Recursive $false` and make sure that the $true property is set.
2. Start the Windows Scheduler.
3. Create a task. Something like this: Program `powershell.exe` arguments `-File "C:\SCRIPT\artemius-azure-authentication-corrector.ps1"` start in `C:\SCRIPT\`
4. In the settings, add a trigger to repeat the launch every 5 minutes, but do not create a new instance! And additionally add a trigger to start when the server is turned on.
