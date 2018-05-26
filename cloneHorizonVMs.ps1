<#
========================================================================
 Created on:   05/25/2018
 Created by:   Tai Ratcliff
 Organization: VMware	 
 Filename:     cloneHorizonVMs.ps1
========================================================================
#>

param(
		[string]$vmConfigXML = "ConfigFileMissing"

)

If (Test-Path ($vmConfigXML)){
    [xml]$vmConfig = Get-Content -Path $vmConfigXML
} else {
    throw "$vmConfigXML does not exist or can not be found"
}

cls

Get-Module –ListAvailable VM* | Import-Module
Write-Host `n `n `n `n `n `n `n

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping" -Status "Sleeping..." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping" -Status "Sleeping..." -SecondsRemaining 0 -Completed
}

# Connect to Management vCenter Server
$vcServer = $vmConfig.csConfig.mgmtvCenter
$hznServiceAccount = $vmConfig.csConfig.hznServiceAccount.Username
$hznServiceAccountPassword = $vmConfig.csConfig.hznServiceAccount.Password
Connect-VIServer -Server $vcServer -User $hznServiceAccount -Password $hznServiceAccountPassword -Force | Out-Null
Write-Host "Successfully connected to $vcServer" -ForegroundColor Black -BackgroundColor Green `n

# Create a folder for the EUC Management VMs
$folderName = $vmConfig.csConfig.connectionServers.folder
$datacenterName = $vmConfig.csConfig.connectionServers.datacenterName
if(!(get-Folder -Name $folderName -ErrorAction Ignore)){
    Write-Host "The $foldername VM folder does not exist, creating a new folder" -BackgroundColor Yellow -ForegroundColor Black `n
    (Get-View (Get-View -viewtype datacenter -filter @{"name"="$datacenterName"}).vmfolder).CreateFolder("$folderName") | Out-Null
}
if(get-Folder -Name $folderName -ErrorAction Ignore){
    Write-Host "Found an existing $foldername VM Folder in vCenter. This is where the Connection Servers will be deployed." -BackgroundColor Yellow -ForegroundColor Black `n
}

$vmObjectArray = @()

# Clone new Connection Servers

for($i = 0; $i -lt $vmConfig.csConfig.connectionServers.horizonCS.count; $i++){ 
    # Guest Customization
    $csName = $vmConfig.csConfig.connectionServers.horizonCS[$i].Name
    $ipAddress = $vmConfig.csConfig.connectionServers.horizonCS[$i].IP
    $subnetMask = $vmConfig.csConfig.connectionServers.subnetMask
    $gateway = $vmConfig.csConfig.connectionServers.gateway
    $dnsServer = $vmConfig.csConfig.connectionServers.dnsServerIP
    $orgName = $vmConfig.csConfig.connectionServers.orgName
    $domainName = $vmConfig.csConfig.connectionServers.domainName
    $timeZone = $vmConfig.csConfig.connectionServers.timeZone 
    $domainJoinUser = $vmConfig.csConfig.connectionServers.domainJoinUser
    $domainJoinPass = $vmConfig.csConfig.connectionServers.domainJoinPass
    $productKey = $vmConfig.csConfig.connectionServers.productKey

    # New VM
    $datastore = $vmConfig.csConfig.connectionServers.datastore
    $csTemplate = $vmConfig.csConfig.connectionServers.fullCloneTemplate
    $diskFormat = $vmConfig.csConfig.connectionServers.diskFormat
    $cluster = $vmConfig.csConfig.connectionServers.cluster
    $osCustomizationSpecName = $csName + "-CustomizationSpec"
    $portGroup = $vmConfig.csConfig.connectionServers.portGroup
    
    Write-Host "Now provisioning $csName" -BackgroundColor Blue -ForegroundColor Black `n
    
    # Linked Clone - The VM must be a VM and not converted to a template, and have a valid Snapshot
    $deployLinkedClones = $vmConfig.csConfig.connectionServers.deployLinkedClones
    [System.Convert]::ToBoolean($deployLinkedClones) | Out-Null
    $referenceSnapshot = $vmConfig.csConfig.connectionServers.referenceSnapshot

    # Check if VM already exists in vCenter. If it does, skip to the next VM
    If(Get-VM -Name $csName -ErrorAction Ignore){
        Write-Host "$csName already exists. Moving on to next VM" -ForegroundColor Black -BackgroundColor Yellow `n
        Continue
    }

    # If a Guest Customization with the same name already exists then we will remove it. This will make sure that we get the correct settings applied to the VM
    If(Get-OSCustomizationSpec -Name $osCustomizationSpecName -ErrorAction Ignore){
        Remove-OSCustomizationSpec -OSCustomizationSpec $osCustomizationSpecName -Confirm:$false
    }
    
    # Create a new Guest Customization for each VM so that we can configure each OS with the correct details like a static IP    
    New-OSCustomizationSpec -Name $osCustomizationSpecName -Type NonPersistent -OrgName $orgName -OSType Windows -ChangeSid -DnsServer $dnsServer -DnsSuffix $domainName -AdminPassword $hznServiceAccountPassword -TimeZone $timeZone -Domain $domainName -DomainUsername $domainJoinUser -DomainPassword $domainJoinPass -ProductKey $productKey -NamingScheme fixed -NamingPrefix $csName -LicenseMode Perserver -LicenseMaxConnections 5 -FullName administraton -Server $vcServer | Out-Null
    $osCustomization = Get-OSCustomizationSpec -Name $osCustomizationSpecName | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $ipAddress -SubnetMask $subnetMask -DefaultGateway $gateway -Dns $dnsServer
    If(Get-OSCustomizationSpec -Name $osCustomizationSpecName -ErrorAction Ignore){
        Write-Host "$osCustomizationSpecName profile has been created for $csName" -ForegroundColor Black -BackgroundColor Green `n
    } Else {
        Write-Host "$osCustomizationSpecName failed to create for $csName" -ForegroundColor Black -BackgroundColor Red `n
    }

    # For testing purposes Linked Clones can be used. For Production full clones must be used. 
    If($deployLinkedClones -eq "True"){
        New-VM -LinkedClone -ReferenceSnapshot $referenceSnapshot -Name $csName -ResourcePool $cluster -Location $folderName -Datastore $datastore -OSCustomizationSpec $osCustomizationSpecName -DiskStorageFormat $diskFormat -Server $vcServer -VM $csTemplate -ErrorAction Stop | Out-Null
        If(Get-VM -Name $csName -ErrorAction Ignore){
            Write-Host "$csName has been provisioned as a Linked Clone VM" -ForegroundColor Black -BackgroundColor Green `n
        }
    } Else {
        Write-Host "$csName is now provisioning" -ForegroundColor Black -BackgroundColor Green `n
        New-VM -Name $csName -Datastore $datastore -DiskStorageFormat $diskFormat -OSCustomizationSpec $osCustomizationSpecName -Location $folderName -Server $vcServer -Template $csTemplate -ResourcePool $cluster | Out-Null
        If(Get-VM -Name $csName -ErrorAction Ignore){
            Write-Host "$csName has been provisioned as a Full Clone VM" -ForegroundColor Black -BackgroundColor Green `n
        }
    }

    # Power on the VMs after they are cloned so that the Guest Customizations can be applied
    Start-VM -VM $csName -Confirm:$false | Out-Null
    Write-Host "Powering on $csName VM" -ForegroundColor Black -BackgroundColor Yellow `n

    #Make sure the new server is provisioned to the correct network/portgroup and set to "Connected"
    Get-VM $csName | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $portGroup -Confirm:$false | Out-Null
    Get-VM $csName | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false | Out-Null

    # Adding each VM to an array of VM Objects that can be used for bulk modifications.
    If(Get-VM -Name $csName){
        $vmObjectArray += (Get-VM -Name $csName)
    } Else {
        throw "$csName failed to be created"
    }
}

# Set up a DRS anti-affinity rule to keep the Connection Servers running on separate hosts
$affinityRuleName = $vmConfig.csConfig.connectionServers.affinityRuleName
if(!(Get-DrsRule -Cluster $cluster -Name $affinityRuleName -ErrorAction Ignore)){
    If($vmObjectArray){ 
        New-DrsRule -Name $affinityRuleName -Cluster $cluster -VM $vmObjectArray -KeepTogether $false -Enabled $true | Out-Null
    }
    if(Get-DrsRule -Cluster $cluster -Name $affinityRuleName -ErrorAction Ignore){
        Write-Host "Created a DRS anti-affinity rule for the Connection Servers: $affinityRuleName" -ForegroundColor Black -BackgroundColor Green `n
    }
}

$requestCASignedCertificate = $vmConfig.csConfig.certificateConfig.requestCASignedCertificate
[System.Convert]::ToBoolean($requestCASignedCertificate) | Out-Null

If($requestCASignedCertificate -eq "True"){
    # Wait for a while to ensre the OS Guest Customization is compute and VMTools has started working before trying to execute the in-guest tasks
    Write-Host "Pausing the script while we wait until the VMs are ready to execute in-guest operations." -ForegroundColor Black -BackgroundColor Yellow
    Write-Host "This will take up to 5 minutes for Guest Opimization to complete and VMTools is ready.  " -ForegroundColor Black -BackgroundColor Yellow `n
    Start-Sleep -Seconds (60*5)
    
    # Apply CA Signed Certificates to each of the Connection Server VMs
    $deploymentSourceDirectory = $vmConfig.csConfig.deploymentSourceDirectory
    $deploymentDestinationDirectory = $vmConfig.csConfig.deploymentDestinationDirectory
    $pfxPassword = $vmConfig.csConfig.connectionServers.pfxPassword
    $requestCASignedCertificate = $vmConfig.csConfig.certificateConfig.requestCASignedCertificate
    $caName = $vmConfig.csConfig.certificateConfig.caName
    $country = $vmConfig.csConfig.certificateConfig.country
    $state = $vmConfig.csConfig.certificateConfig.state
    $city = $vmConfig.csConfig.certificateConfig.city
    $organisation = $vmConfig.csConfig.certificateConfig.organisation
    $organisationOU = $vmConfig.csConfig.certificateConfig.organisationOU
    $templateName = $vmConfig.csConfig.certificateConfig.templateName
    $friendlyName = $vmConfig.csConfig.certificateConfig.friendlyName

    $createDestinationDirectoryCMD = "If(!(Test-Path -Path $deploymentDestinationDirectory)){New-Item -Path $deploymentDestinationDirectory -ItemType Directory | Out-Null}"

    for($i = 0; $i -lt $vmConfig.csConfig.connectionServers.horizonCS.count; $i++){
        $csName = $vmConfig.csConfig.connectionServers.horizonCS[$i].Name
        $certScriptFile = "$deploymentSourceDirectory\Request-Certificate.ps1" -replace "(?!^\\)\\{2,}","\"
        $certScriptDestinationFile = "$deploymentDestinationDirectory\Request-Certificate.ps1" -replace "(?!^\\)\\{2,}","\"
        $commonName = "$csName.$domainName"

        $certRequestCommand = "$certScriptDestinationFile -CN ""$commonName"" -CAName ""$caName"" -Country ""$country"" -State ""$state"" -City ""$city"" -Organisation ""$organisation"" -Department ""$organisationOU"" -FriendlyName ""$friendlyName"" -TemplateName ""$templateName"""

        If((Get-VM $csName).ExtensionData.Guest.ToolsRunningStatus.toupper() -eq "GUESTTOOLSRUNNING"){
            Write-Host "Copying certificate configuration scripts to $csName" -ForegroundColor Black -BackgroundColor Yellow `n
            # Use VMTools to run a script that will create create the destination folder if it doesn't already exist
            Invoke-VMScript -ScriptText $createDestinationDirectoryCMD -VM $csName -guestuser $hznServiceAccount -guestpassword $hznServiceAccountPassword -ErrorAction Stop 
            # Use VMTools to copy the certificate request powershell script to the destination folder
            Copy-VMGuestfile -LocalToGuest -source $certScriptFile -destination $deploymentDestinationDirectory -Force:$true  -VM $csName -guestuser $hznServiceAccount -guestpassword $hznServiceAccountPassword  -ErrorAction SilentlyContinue

            Write-Host "Requesting a new certificate for $csName" -ForegroundColor Black -BackgroundColor Yellow `n
            # Use VMTools to execute the certificate request powershell script within the guest OS on the destination server
            $requestCert = Invoke-VMScript -ScriptText $certRequestCommand -VM $csName -guestuser $hznServiceAccount -guestpassword $hznServiceAccountPassword -ErrorAction Stop 
            $requestCert.ScriptOutput
        } Else {
            Write-Host "VMTools on $csName is not responding. Unable to copy certificate to the VM" -ForegroundColor White -BackgroundColor Red `n
        }
    }
}

Write-Host "Script Completed" -ForegroundColor Black -BackgroundColor Green `n



