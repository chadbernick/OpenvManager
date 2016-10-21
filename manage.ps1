<# 
       .Synopsis 
        This is a Powershell script to create or delete virtual machines.
       .Example
        Manage.ps1 Deploy -count 2
        This will prompt for your username: domain\user format.
        It will prompt for your password.
        It will ask for a machine name (example:usindmvweb)
        It will then create 2 virtual machines named usindmvweb001 and usindmvweb002 on the most available carmel host& 
        most avilable carmel datastore.
        .Example
        Manage.ps1 Deploy -user domain\user -password ***** -ComputerName testbuild -site fishers -flavor small -customization "W2k8 dp.net"
        This will create a virtual machine called testbuild001 using vmware template fishers.w.stable with the 
        vmware w2k8 dp.net customizations on the most available datastore in fishers with 2 CPUs and 1GB RAM
        on the most available vhost.
        Valid Flavors:
        micro:  1CPUs, base RAM
        small:  2CPUs, 1024MB RAM
        medium: 2CPUs, 2048MB RAM
        large:  4CPUs, 4096MB RAM
        .Example
        Manage.ps1 Destroy -ComputerName usindmvtestbuild1
        This will remove the named server from inventory and delete it from the datastore.
        .Description
        The script will make vms.  
        USAGE 
                    Manage.ps1 [operation] <options>
        OPERATIONS  
                    Deploy          -creates vms from template
                    Destroy         -deletes named vms from inventory and datastore
            DEPLOY      
                    computername    -Name of vmware guests (will automatically add 00n suffix)
            OPTIONS 
                    count           -# of virtual machines to create     (default value: 1)
                    vhost           -virtual host to deploy guests to    (default value: auto)
                    site            -location to deploy the guest       (default value: carmel)
                    OS              -Operating System Selector           (default value: windows)
                    flavor          -VM size                            (default value: micro)
                    template        -virtual machine teplate for guest   (default value: $site.w.stable)
                    customization   -vmware customization rule to apply  (default value: W2k8 DP.NET)
                    datastore       -vmware datastore for deployment     (default value: auto)
                    cost            -specify cost center                 (default value: 0)
            DESTROY
                    computername    -Name of vmware guest
            
            EXAMPLE
            manage.ps1 Deploy -computername usindmvweb -count 2 -datastore XIO_DS7
            
            Valid Flavors:
            micro:  1CPUs, base RAM
            small:  2CPUs, 1024MB RAM
            medium: 2CPUs, 2048MB RAM
            large:  4CPUs, 4096MB RAM
            
       .Notes 
        NAME: MANAGE.PS1
        AUTHOR: chad@cterminal.com
        REFERENCE DESIGN: This requires a common infrasturure design pattern.  See http://cterminal.com/boot/blueprint.shtml
        LASTEDIT: 05/24/2013 13:30:58 
        KEYWORDS: 
       .Link 
        empty
    #>
    
# Getting the parameters
[CmdletBinding()]
Param(
[Parameter(Mandatory=$True,
           HelpMessage="Type DEPLOY to create virtual machines `nType DESTROY to delete virtual machines.")]
[ValidateSet("Deploy", "Destroy")]
[string]$global:Operation,
[Parameter(Mandatory=$True,
           HelpMessage="Type your username in the DOMAIN\USER format.")]
[string]$User,
#[Parameter(Mandatory=$True)]
#[string]$Password = Read-host -Prompt "Enter your password" -AsSecureString,
[Parameter(Mandatory=$True)]
[string]$ComputerName,
[Parameter(Mandatory=$False,
           HelpMessage="Chose your operating system: `nWindows `nLinux")]
[ValidateSet("Windows", "Linux")]
[string]$OS="Windows",
[Parameter(Mandatory=$False,
           HelpMessage="Chose your operating system Version: `n2003 `n2008 `n2008R2 `n2012 `nLegacy `nStable `nCurrent")]
[ValidateSet("2003", "2008", "2008R2", "2012", "Legacy", "Stable", "Current")]
[string]$Version="Stable",
[Parameter(Mandatory=$False,
           HelpMessage="Chose your flavor: `nMicro `nSmall `nMedium `nLarge")]
[ValidateSet("Micro", "Small", "Medium", "Large")]
[string]$Flavor="Micro",
[Parameter(Mandatory=$False)]
$count="1",
[Parameter(Mandatory=$False,
        HelpMessage="Enter cost center.")]
$cost="0",
[Parameter(Mandatory=$False)]
$vhost="AUTO",
[Parameter(Mandatory=$False)]
$Site="Carmel",
[Parameter(Mandatory=$False)]
$customization="W2K8 DP.net",
[Parameter(Mandatory=$False)]
$vcenter="##INSERT VCENTER SERVER IP or DNS NAME HERE",
[Parameter(Mandatory=$False)]
$Datastore="AUTO"
)
$SecurePassword = Read-host -Prompt "Enter your password" -AsSecureString
$Password = [runtime.interopServices.marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringtoBSTR($SecurePassword))
###
if (($OS -ieq "Windows") -and ($version -eq "2008") -or ($version -eq "2008R2")){
$template="$site.w.stable"
}
elseif (($OS -ieq "Windows") -and ($version -ieq "2012")){
$template="$site.w.current"
}
elseif (($OS -ieq "Windows") -and ($version -ieq "Current")){
$template="$site.w.current"
}
elseif (($OS -ieq "Windows") -and ($version -ieq "Stable")){
$template="$site.w.stable"
}
elseif (($OS -ieq "Windows") -and ($version -ieq "2003")){
$template="$site.w.legacy"
}
elseif (($OS -ieq "Windows") -and ($version -ieq "Legacy")){
$template="$site.w.legacy"
}
elseif (($OS -ieq "Linux") -and ($version -ieq "Current")){
$template="$site.l.current"
$customization=$null
}
elseif (($OS -ieq "Linux") -and ($version -ieq "Stable")){
$template="$site.l.current"
$customization=$null
}
elseif (($OS -ieq "Linux") -and ($version -ieq "Legacy")){
write-host "Linux Legacy is not supported"
$customization=$null
}

# If the operation is to deploy do this bit of code
#create an empty array called 'array'
$array = @()
$targethosts = @()
#if(($SecurePassword -eq $null)){
#$credVCAdmin = New-object system.management.automation.pscredential -ArgumentList $user,$Password
function Update-VNTitleBar() {
        ## check to see if there are any currently connected servers
        if ($global:DefaultVIServers.Count -gt 0) {
                    ## at least one connected server -- modify the window title variable accordingly
            $strWindowTitle = "[PowerCLI] Connected to {0} server{1}:  {2}" -f $global:DefaultVIServers.Count, `
$(if ($global:DefaultVIServers.Count -gt 1) {"s"}), (($global:DefaultVIServers | %{$_.Name}) -Join ", ")
        } else {
            ## no connected servers, modify the window title variable to show "not connected"
                    $strWindowTitle = "[PowerCLI] Not Connected"
        } ## end else
        ## change the window title
        $host.ui.RawUI.WindowTitle = $strWindowTitle
    }
#}
#else{write-host "Using cached Credentials."
#    }

$deployjob= function Get-Deploy(){
    #Load the VMware PowerCLI bits
    if((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null){
    Add-PSSnapin VMware.VimAutomation.Core
    #Ignore Cert problems
    Set-PowerCLIConfiguration -InvalidCertificateAction "Ignore" -Confirm:$false
    }
    #Connect to my vcenter instance as username from the $User parameter with a password from the $Password parameter
    Connect-VIServer -Server $vcenter -Protocol https -User $User -Password $Password
    (Update-VNTitleBar)

    $avalibleServers = New-Object System.Collections.ArrayList
    $runningServerCount = 1

   while($avalibleServers.Count -ne $Count) {
            $tempvm = "$ComputerName"+$runningServerCount.tostring().padleft(3,'0')
            $tvm = (Get-VM $tempvm -ErrorAction SilentlyContinue)
            if($tvm -eq $null) {
                [void]$avalibleServers.Add($tempvm)             
            }
            $runningServerCount++
        }
foreach ($vm in $avalibleServers){
##Create Guest VM(s)
    #Find Datastore with Enough Room
    Function FindDS {
    Write-Host "Detecting most available Datastore." -Foregroundcolor magenta
    $templateview = get-view -id (get-template $template).id
    $templatesumKB = ($templateview.config.hardware.device | ? {$_ -is [vmware.vim.VirtualDisk]}).capacityinKB
    $templatelocation = ($templateview.config.datastoreurl | %{$_.name})
    $locationsplit=$templatelocation.split("_")
    $locationprefix=$locationsplit[0]
    if (($locationprefix -ieq "NEX")) {$prefix="NEX|XIO"}
    else {$prefix=$Locationprefix} 
    $LocalDatastores = get-datastore | where {$_.Name -match "$Prefix"} | select-Object -Property Name, FreeSpace
    $FilteredDatastores= $localDatastores | where {$_.Name -notmatch "ISO|TEMPLATE|CRFILE*|SQL|FILES*|INS13FILE|MIGRATION|DMZ|HPC|UC|Vmware|VDI"}
    $ChosenDatastore = $FilteredDatastores | Sort-Object -Descending -Property FreeSpace | Select-Object -Property Name -First 1
    $global:DSFriendlyname = $chosendatastore.name
    Write-Host "$DSFriendlyname has been selected as most available in your template region. `nChecking for available disk space." -Foregroundcolor magenta
    $DSQUERY=Get-Datastore $DSFriendlyname | select Name, @{N="FreeSpace";E={[Math]::Round($_.FreeSpaceMB)}}
    $SpaceRequired=$templatesumKB * 1.2/1MB #to validate Datastore must have tempalte + 20% space avaailble.
    $DSFreeSpace=$DSQUERY.FreeSpace
        if (($DSFreeSpace -lt $SpaceRequired)){
        Write-Host "!! Datastores have insufficent free space for this operation !! `nAdd capacity to complete this operation." -ForeGroundColor Yellow
        Exit
        }
        else {
        Write-host "$DSFriendlyname Passed Space Check" -Foregroundcolor Green
        }
    }

if (($Datastore -ieq "Auto")){((FindDS))}
else {$DSQUERY=Get-Datastore $Datastore | select Name, @{N="FreeSpace";E={[Math]::Round($_.FreeSpaceMB)}}
    $SpaceRequired=$templatesumKB * 1.2/1MB #to validate Datastore must have tempalte + 20% space avaailble.
    $DSFreeSpace=$DSQUERY.FreeSpace
        if (($DSFreeSpace -lt $SpaceRequired)){
        Write-Host "!! Datastore $Datastore has insufficent free space for this operation !! `nAdd capacity to complete this operation." -ForeGroundColor Yellow
        Exit
        }
        else {
        Write-host "$Datastore Passed Space Check" -Foregroundcolor Green
        $DSFriendlyname = $datastore
        }
    
    }

Function GetPercentages() {
    write-host "Finding most available host in selected region." -Foregroundcolor magenta
    $sitematch = get-folder -location "SITES" |where {$_.Name -match "$site"} |select Name
    $sitematch = $sitematch[$sitematch.Count -1].name
    if (($sitematch -ieq "carmel")){
        $site = "production"
        $sitematch = "production"}
    if (($site -ieq $sitematch)) {
        $targethosts = get-vmhost -location $site |select Name, MemoryUsageMB, MemoryTotalMB, cpuusagemhz, cputotalmhz
        foreach ($targethost in $targethosts){
        $targethost | add-member NoteProperty PercentMemory ($targethost.MemoryUsageMB/$targethost.MemoryTotalMB *100)
        $targethost | add-member NoteProperty PercentCPU ($targethost.cpuusagemhz/$targethost.cputotalmhz *100)
        $targethost
        }
        $global:myhosts=$targethosts | select Name, PercentMemory, PercentCPU
        }
    else {
    write-host "Something went wrong.  I couldn't find your deployment option.  `Check your site name for spelling errors. `-or-`Try specifiying a specifc virtual host with the -vhost parameter." -Foregroundcolor Yellow
    } 
        }
    
    if (($vhost -ieq "Auto")){
    $targethosts = GetPercentages | sort PercentMemory -descending | select Name, PercentMemory, PercentCPU
    #Calculate the Average Memory
    [int]$Averagemem = 0
    [int]$Averagecpu = 0
    [int]$intCount = 0
    foreach ($targethost in $targethosts){
        $Averagemem += $targethost.PercentMemory
        $Averagecpu += $targethost.PercentCPU
        $intCount++
    }
    $Averagemem /= $intCount
    $Averagecpu /= $intCount
    #Display the average memory used
    write-host ("Average MEM usage on virtual hosts in $site is " + $Averagemem +"%") -Foregroundcolor magenta
    write-host ("Average CPU usage on virtual hosts in $site is " + $Averagecpu +"%") -Foregroundcolor magenta
    #Display the hosts
    #$targethosts | select Name, PercentMemory, PercentCPU
      if (($myhosts.count -gt 0)){
    $hostserver = $myhosts[$myhosts.Count -1].Name}
    else {$hostserver = $myhosts.name}

    write-host "$hostserver was selected as the most availble in site $site" -Foregroundcolor magenta
    }
    else {Write-host "Using specific Host $vhost" -Foregroundcolor Green
    $hostserver = $vhost
    }
    #CREATE the VMS
    Write-Host "CLONING -Name $vm -Template $template -Host $hostserver -DS $DSFriendlyname -folder $site -Custom $customization" -ForegroundColor Green
    Exit
    New-VM -Name $vm -Template $template -Host $hostserver -Datastore $DSFriendlyname -folder $site -OSCustomizationSpec  $customization -Confirm:$false
if ($vm.error) {
    Write-Host "Error in deploying $vmname" -ForegroundColor Red
    Exit
    }

    if (($flavor -ieq "micro")){
        Write-Host "Flavoring Guest $vm MICRO" -ForegroundColor Green
        Set-VM $vm -Confirm:$false -Description "OS : $OS `nFLAVOR: micro `nCOST CENTER : $cost `nFROM TEMPLATE : $template" -RunAsync
        }

    elseif (($flavor -ieq "small")){
        Write-Host "Flavoring Guest $vm SMALL" -ForegroundColor Green
        Set-VM $vm -numCPU "2" -MemoryMB "1024" -Confirm:$false -Description "OS : $OS `nFLAVOR: small `nCOST CENTER : $cost `nFROM TEMPLATE : $template" -RunAsync
        }

    elseif (($flavor -ieq "medium")){
        Write-Host "Flavoring Guest $vm MEDIUM" -ForegroundColor Green
        Set-VM $vm -numCPU "2" -MemoryMB "2048" -Confirm:$false -Description "OS : $OS `nFLAVOR: medium `nCOST CENTER : $cost `nFROM TEMPLATE : $template" -RunAsync
        }

    elseif (($flavor -ieq "large")){
        Write-Host "Flavoring Guest $vm LARGE" -ForegroundColor Green
        Set-VM $vm -numCPU "4" -MemoryMB "4096" -Confirm:$false -Description "OS : $OS `nFLAVOR: large `nCOST CENTER : $cost `nFROM TEMPLATE : $template" -RunAsync
        }
    }
    }


# If the operation is to Destroy do this bit of code
function Get-Destroy(){
    #Load the VMware PowerCLI bits
    if((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null){
    Add-PSSnapin VMware.VimAutomation.Core
    #Ignore Cert problems
    Set-PowerCLIConfiguration -InvalidCertificateAction "Ignore" -Confirm:$false
    }
    #Connect to my vcenter instance as username from the $User parameter with a password from the $Password parameter   
    Connect-VIServer -Server $vcenter -Protocol https -User $User -Password $Password
    (Update-VNTitleBar)
    #Delete Guest VM from inventory and datastore
    Remove-VM -DeletePermanently -VM $ComputerName
    }

if (($Operation -ieq "Deploy")){
    write-host "Deploy Invoked"
    Get-Deploy
    #start-job -InitializationScript $deployjob -Scriptblock {Get-Deploy $args[0] $args[1] $args[3] $args[1] $args[4] $args[5] $args[6] $args[7] $args[8] $args[9] $args[10] $args[11] $args[12]} -ArgumentLIst @($Operation, $OS, $ComputerName, $Version, $Flavor, $Count, $Cost, $vHost, $Site, $Customization, $Datastore, $credVCAdmin)
}
else {
    write-host "Destroy Invoked"
    Get-Destroy
    }

