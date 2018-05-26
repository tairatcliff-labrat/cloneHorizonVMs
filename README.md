# cloneHorizonVMs

What this script will do:

Clone a template VM for each of the Connection Servers listed in the XML document
[Optional] The VMs can be deployed as linked clones or full clones. Linked clones are really handy for testing or lab environments.
OS Guest Customizations are created for each VM. These include all of the static IP settings, Domain join details, license keys, and everything else that is needed to configure each VM.
A VM Folder will be created and all Connection Servers will be deployed within the folder.
A DRS VM/Host anti-affinity group will be created. All Connection Servers will be joined to the group and set to run on different hosts.
[Optional] All connection servers will automatically request CA Signed certificates and install them in the LocalMachine\Personal certificate store. The friendly name is set to “VDM” automatically.
 
Pre-requisites

Create a horizon service account in Active Directory (i.e. svc_horizon).
Give the horizon service account administrator access to the management vCenter Server.
The service account shouldn’t need admin access to request certificates, but if there are any issues I can easily create an input for a Certificate Administrator account that has permission to request certificates from the CA server.

Log on to a Helper VM or Jumpbox as the Horizon Service Account.
Install PowerCLI.
Create a local directory for the source files (i.e. c:\Binaries).
Copy the “Request-Certificate.ps1” to the local source files directory (this file will be copied to each of the Connection Servers via VMTools and executed locally).
Update all of the XML settings in the vmConfigXML.xml file.

Build a CS template VM with the following Settings:
Server 2012 R2.
CPU, RAM and Storage configured as per Connection Server requirements.
Single NIC - I haven’t tried deploying with multiple NICs, so I’m not sure how the script will handle this yet.
Static IP – I haven’t allowed DHCP. This would require changes to the OS Guest Customization components and I don’t see a need for it.
Configure Server Name.
Domain Joined – Probably not required because the OS Guest Customization will join the VMs to the domain anyway.
Create the local Deploy folder (i.e. C:\Deploy) – This isn’t actually required. I have written into the scripts a check to see if the folder exists and if it doesn’t, we will automatically create it anyway.
Add the Horizon Service Account to the local Administrators group.
Installed PowerCLI – Not really required. I am not using any PowerCLI modules as part of my script, but it is nice to have PowerCLI installed on the Connection Servers anyway.
Copy and install VMware.HV.Helper to PowerShell and PowerCLI modules – This is more relevant to the scripts to automate the build rather than deploying the VMs.
Disabled Windows Firewall - Not sure if this is actually required or not, but I do it as a force of habbit anyway.
Disable UAC – Disable User Account control, otherwise we can’t execute scripts remotely that require admin elevation (like certificate requests). If we need to overcome this then I can look at other software like psexec.
Edit Group Policy to disable “UAC: Run all administrators in Admin Approval Mode” - Computer > Windows Settings > Security Settings > Local Policies > Security Options – Without this additional setting, UAC still imposes some restrictions on the local administrator account. Changing this setting will now automatically elevate scripts to run as Administrator remotely.
Set-ExecutionPolicy Unrestricted – I don’t think this is necessary, but I do it anyway.

If you want to deploy Linked-Clones, you need to ensure the reference VM is not converted to a template and you also need to take a snapshot of the VM.

If you want to deploy Full clones, you need to convert the reference VM to a template.
Execute the script with the parameter -vmConfigXML and point it to the location of the updated XML file:
“.\cloneHorizonVMs-certRequest.ps1 -vmConfigXML C:\Temp\vmConfigXML-certs.xml”
