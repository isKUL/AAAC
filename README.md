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
