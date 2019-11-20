#requires -RunAsAdministrator
<#
.SYNOPSIS
This script is designed to automatically balance the recovery VRAs based on a maximum number of protected VMs per recovery VRA (Host)
.DESCRIPTION
This script will automatically ensure that no VRA is protecting more VMs than specified within this script, where possible.
MUST be run less frequently than the resources report which must be configured to daily within site settings under reports on the target ZVM. (default is daily)
.VERSION
Applicable versions of Zerto Products script has been tested on. Unless specified, all scripts in repository will be 5.0u3 and later. If you have tested the script on multiple
versions of the Zerto product, specify them here. If this script is for a specific version or previous version of a Zerto product, note that here and specify that version
in the script filename. If possible, note the changes required for that specific version.
.LEGAL
Legal Disclaimer:
 
----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
 
In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages. The entire risk arising out of the use or
performance of the sample scripts and documentation remains with you.
----------------------
#>
################################################
# Configure the variables below, use the recovery site ZVM
################################################
$ZertoServer = "<ZVMIP>"
$ZertoPort = "9669"
$ZertoUser = "administrator"
$ZertoPassword = "Password"
$BaseURL = "https://" + $ZertoServer + ":" + $ZertoPort + "/v1/"
$SiteName = "<ZVMSiteName>"
$maxVMs = "9" #Max Number of VMs per Recovery VRA (Host)

################################################
# Setting Cert Policy - required for successful auth with the Zerto API without connecting to vsphere using PowerCLI
################################################
add-type @"
 using System.Net;
 using System.Security.Cryptography.X509Certificates;
 public class TrustAllCertsPolicy : ICertificatePolicy {
 public bool CheckValidationResult(
 ServicePoint srvPoint, X509Certificate certificate,
 WebRequest request, int certificateProblem) {
 return true;
 }
 }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

################################################
# FUNCTIONS DEFINITIONS
################################################

#Authenticates with Zerto's APIs, Creates a Zerto api session and returns it, to be used in other APIs
function getZertoXSession (){
    #Authenticating with Zerto APIs
    $xZertoSessionURI = $BASEURL + "session/add"
    $authInfo = ("{0}:{1}" -f $ZertoUser,$ZertoPassword)
    $authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
    $authInfo = [System.Convert]::ToBase64String($authInfo)
    $headers = @{Authorization=("Basic {0}" -f $authInfo)}
    $xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $headers -Method POST

    #Extracting x-zerto-session from the response, and adding it to the actual API
    $xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session")
    return $xZertoSession 
}

#Get a site identifier by invoking Zerto's APIs given a Zerto API session and a site name
function getSiteIdentifierByName ($siteName){
    $url = $BASEURL + "virtualizationsites"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 100 -Headers $zertoSessionHeader -ContentType "application/json"
	    ForEach ($site in $response) {
      if ($site.VirtualizationSiteName -eq $siteName){
            return $site.SiteIdentifier
        }
    }
}

# Find number of VMs per VRA (Host)
function getVmsPerTargetHost {
#List Site Hosts
$Hostsurl = $BASEURL + "virtualizationsites/" + $SiteID + "/hosts"
$SiteHosts = Invoke-RestMethod -Uri $Hostsurl -TimeoutSec 100 -Headers $zertoSessionHeader -ContentType "application/json" -Method GET

#Get number of VMs per Recovery VRA (Host)
$hosts = @()

    ForEach ($name in $SiteHosts) {

        $hostname = $name.VirtualizationHostName
        $hostid = $name.HostIdentifier
        $vmCount = getReport $hostname
        $vmsObject= New-Object PSObject -Property @{
                        HostID = $hostid
                        VMCount = $vmCount
                    }
        $hosts += $vmsObject
    }
return $hosts
}

function getReport ($TargetHostName){
    # Setting dates to retrieve data from past 24 hours 
    $StartDateTime = (get-date).AddDays(-1).ToString("yyyy-MM-dd") 
    $EndDateTime = get-date -Format "yyyy-MM-dd"
    $i = 0
    # QueryResourceReport
    $url = "https://" + $ZertoServer + ":"+$ZertoPort + "/v1/reports/resources?startTime=" + $StartDateTime + "&endTime=" + $EndDateTime + "&pageSize=1000"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 100 -Headers $zertoSessionHeader -ContentType "application/json"
	    ForEach ($vm in $response) {
            if ($vm.RecoverySite.Compute.HostName -eq $TargetHostName){
            $i++
        }
        
    }
    return $i
}

# Find target Host of every VM
function getTargetHostList {
# List Site Hosts
$Vpgsurl = $BASEURL + "vpgs"
$Vpgs = Invoke-RestMethod -Uri $Vpgsurl -TimeoutSec 100 -Headers $zertoSessionHeader -ContentType "application/json" -Method GET

#  Find target Host of every VM
$TargetHosts = @()

    ForEach ($vpg in $Vpgs) {
        $VpgId = $vpg.VpgIdentifier
        $CreateVpgSettingsUrl = $BASEURL + "vpgsettings"
        $CreateVpgSettingsBody = "{""VpgIdentifier"":""$VpgId""}"
        $VPGSettingsIdentifier = Invoke-RestMethod -Uri $CreateVpgSettingsUrl -TimeoutSec 100 -Headers $zertoSessionHeader -Body $CreateVpgSettingsBody -ContentType "application/json" -method POST
        $VPGSettingsURL = $BASEURL + "vpgSettings/" + $VPGSettingsIdentifier + "/vms"
        $response = Invoke-RestMethod -Uri $VPGSettingsURL -Headers $zertoSessionHeader -ContentType "application/json" -method GET
            ForEach ($vm in $response) {
                $VmId = $vm.VmIdentifier
                $TargetHostId = $vm.Recovery.HostIdentifier
                $VmTargetObject= New-Object PSObject -Property @{
                                TargetHostID = $TargetHostId
                                VmID = $VmId                                
                                VpgSettingsId = $VPGSettingsIdentifier
                            }
                $TargetHosts += $VmTargetObject
            }
    }
return $TargetHosts
}

# Find Oversubscribed Target VRAs (Hosts)
function OversubscribedVRAs {
        ForEach ($vm in $VMBalance) {
            if ($vm.VMCount -gt $maxVMs){
                $hostID = $vm.HostID
                ChangeVMsVRA $hostID
        }
        
    }
}

# Change VM Recovery VRAs
function ChangeVMsVRA ($id) {
       ForEach ($vm in $TargetHostList) {
            If ($vm.TargetHostID -eq $id) {
                $CurrentHost = $vm.TargetHostID
                $VmId = $vm.VmID
                $VpgSettingsId = $vm.VpgSettingsID
                $UnderProvisioned = $VMBalance | Where-Object VMCount -lt "$maxVMs"
                $NewHost = $UnderProvisioned.HostID | Select-Object -first 1 
                $VPGSettingsURL = $BASEURL + "vpgSettings/" + $VpgSettingsId
                $ChangeVraBody= "{ ""Vms"": [ { ""Recovery"": { ""HostIdentifier"": ""$NewHost"" }, ""VmIdentifier"": ""$VmId"" } ] }"
                Invoke-RestMethod -Uri $VPGSettingsURL -TimeoutSec 100 -Headers $zertoSessionHeader -Body $ChangeVraBody -ContentType "application/json" -method PUT
                # Adjust number of VMs per VRA Values
                $IncVmCount = $VMBalance | Where-Object HostID -eq $NewHost
                If ($IncVmCount){
                    $IncVmCount.VMCount += 1 
                    }
                $DecVmCount = $VMBalance | Where-Object HostID -eq $CurrentHost
                If ($DecVmCount -and $DecVMCount.VMCount -gt $maxVMs){
                    $DecVmCount.VMCount -= 1 
                    }
                }
       }    
}

# Commit VPGSettings Identifiers Invoking the Change Recovery VRA Task(s)
function CommitVpgSettings {
       $UniqueIds = $TargetHostList.VpgSettingsID | Select-Object -Unique
       ForEach ($id in $UniqueIds) {
                $VpgSettingsCommitId = $id
                $VPGSettingsCommitURL = $BASEURL + "vpgSettings/" + $VpgSettingsCommitId + "/commit"
                Invoke-RestMethod -Uri $VPGSettingsCommitURL -Headers $zertoSessionHeader -ContentType "application/json" -method POST
       }
}

################################################
# Script Starts Here
################################################
# Get Zerto API Session
$xZertoSession = getZertoXSession
$zertoSessionHeader = @{"x-zerto-session"=$xZertoSession}
# Find Site ID from Site Name
$SiteID = getSiteIdentifierByName $SiteName
# Find number of VMs per VRA (Host)
$VMBalance = getVmsPerTargetHost
# Find target VRA (Host) of every VM
$TargetHostList = getTargetHostList
# Find Oversubscribed Target VRAs (Hosts)
OversubscribedVRAs
$VMBalance
# Commit VPGSettings Identifiers
"VPGSettings Commit Task IDs"
CommitVpgSettings
