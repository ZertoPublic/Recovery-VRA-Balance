# Legal Disclaimer
This script is an example script and is not supported under any Zerto support program or service. The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you.

# Recovery-VRA-Balance
This script is designed to automatically balance the recovery VRAs based on a maximum number of protected VMs per recovery VRA (Host).
This script will automatically ensure that no VRA is protecting more VMs than specified within this script, where possible.

# Getting Started
There are two versions of the script. Use RecoveryVRABalanceFor_v7+.ps1 for Zerto version 7.0 and above, or RecoveryVRABalance.ps1 for Zerto 6.5 or below.

Set the variables below including the maximum number of VMs you would like per target VRA. This should be a realistic value based on the number of VMs being protected by Zerto in your environment.

Schedule the script to run daily to keep the target VRAs balanced or run manually as required.  **MUST** be run less frequently than the resources report sample rate which **MUST** be configured to daily within site settings under reports on the target ZVM. (default is daily)

# Prerequisities
## Environment Requirements:
- PowerShell 5.0+
- ZVR 6.0u2 to 6.5uX for RecoveryVRABalance.ps1
- ZVR 7.0+ for RecoveryVRABalanceFor_v7+.ps1

## In-Script Variables:
- ZVM IP
- ZVM User / Password
- ZVM Site Name
- Max VMs per VRA (Host)

# Running Script
Once the necessary requirements have been completed select an appropriate host to run the script from. To run the script type the following from the directory the script is located in:

.\RecoveryVRABalance.ps1 or .\RecoveryVRABalanceFor_v7+.ps1
