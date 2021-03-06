# Get current date/time
$timestamp = Get-Date -Format 'yyyy-MM-dd HH-mm'

# If no $outputFolder was provided, create standard path
if (!$outputFolder) {
	$outputFolder = "C:\Temp\DailyChecks\$($timestamp)"
}
else {
	$outputFolder = Join-Path $outputFolder $timestamp
}
# if parent folder does not exist, create it
if (!(Test-Path -Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}
$dcDiagOutputFile = Join-Path -Path $OutputFolder -ChildPath "dcdiag.txt"
$htmlOutputFile = Join-Path -Path $outputFolder -ChildPath "$($timestamp).html"
$dagHealthCheck = Join-Path -Path $outputFolder -ChildPath "dagHealthCheck.html"

# load Exchange snapin if not present
if ((Get-PSSnapin | Select -ExpandProperty Name) -notcontains 'Microsoft.Exchange.Management.PowerShell.E2010') {
    Add-PSSnapin 'Microsoft.Exchange.Management.PowerShell.E2010' -ErrorAction SilentlyContinue
    if (!$?) {
        Write-Host "Failed to import snapin 'Microsoft.Exchange.Management.PowerShell.E2010'" -ForegroundColor Red
    }
}

# load VMware snapin if not present
if ((Get-PSSnapin | Select -ExpandProperty Name) -notcontains 'VMware.VimAutomation.Core') {
    Add-PSSnapin 'VMware.VimAutomation.Core' -ErrorAction SilentlyContinue
    if (!$?) {
        Write-Host "Failed to import snapin 'VMware.VimAutomation.Core'" -ForegroundColor Red
    }
}

#######################################
###### Load the common functions ######
#######################################
$functions = @(
    'Get-CPUandMemoryUsage.ps1',
    'Test-ADInfrastructure.ps1',
    'Get-LogicalDiskInfo.ps1',
    'Get-ServersUptime.ps1',
    'Get-MailboxServerInformation.ps1',
	'Get-LogDriveInfo.ps1',
    'Check-RequiredServices.ps1',
    'Check-Whitespace.ps1',
	'Test-Wmi.ps1',
    'Get-EsxHostStats.ps1',
    'Get-VMwareDatastores.ps1',
    'get-DAGHealth.ps1',
	'HTMLTable.ps1'
)

# define script root
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
# load the functions
$functions | % {
    . (Join-Path $scriptRoot "\Functions\$_") -as [String]
}

# load the list of servers to be tested
. (Join-Path $scriptRoot "\MCCCServer-List.ps1") -as [String]

# Hype-V Module location

$hyperVmodule = Join-Path $scriptRoot "\Module\HyperV\Hyper-V-Module.psd1"

##############################################################################
##############################################################################
###                                                                        ###
###                            Start the checks                            ###
###                                                                        ###
##############################################################################
##############################################################################


########################################
######          EXCHANGE          ######
########################################


#Declare vaiables

 $CPUMemInfoExchangeResults = @()
 $DiskInfoExchangeResults = @()
 $DbStatusExchangeResults = @()
 $ServicesExchangeResults = @()
 $ExcErrorWmi = @()

Write-Host 'Exchange Checks' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green


### Dag Health chcks
Write-Host 'Running DAG health' -ForegroundColor Green


Check-DAGHealth -Detailed -HTMLFileName $dagHealthCheck

Write-Host 'DAG health Completes' -ForegroundColor Green

Write-Host '============================================' -ForegroundColor Blue
Write-Host 'Exchange checks completed' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Blue



###

Write-Host "Checking CPU / Memory / Disk / Service Status"

foreach ($server in $ExchangeServers){
    if ((Test-Wmi -computername $server.ServerName) -eq "OK") {
    		Write-host "Checking:  " $server.ServerName -ForegroundColor Green

    #CPU and Memory
            $CPUMemInfoExchange = New-Object PSObject -Property @{
                'ServerName' = $server.ServerName;
                'CpuUsage' = Get-CPUandMemoryUsage -ComputerName ($server.ServerName) | select -expandProperty  CPU
                'MemoryUsage' = Get-CPUandMemoryUsage -ComputerName ($server.ServerName) | select  -expandProperty MEM
             }
            
            $CPUMemInfoExchangeResults += $CPUMemInfoExchange | select ServerName, CpuUsage, MemoryUsage | sort ServerName
    #Disk Info        
            
            
            $DiskInfoExchange = Get-LogicalDiskInfo -computername ($server.ServerName) -Thresholds $exchangeDiskThresholds
            $DiskInfoExchangeResults += $DiskInfoExchange   
              

    #ServicesStatus
            $ServicesExchange = Check-RequiredServices -ComputerName ($server.ServerName) -Services ($server.RequiredServices) `
                        | Select MachineName, DisplayName, ServiceName, Status `
                        | Sort MachineName
            $ServicesExchangeResults += $ServicesExchange   

    }
    else {
    $EXCSrvNameTmp = $server.ServerName
    $ExcErrorWmiTmp = New-Object PSObject -Property @{
                'ServerName' = "$EXCSrvNameTmp";
                'WMI-Error' = "ERROR"; 
                'Error' = "Unable to connect to this host via WMI"
                }
    $ExcErrorWmiTmp | Select ServerName, WMI-Error, Error
    $ExcErrorWmi += $ExcErrorWmiTmp | Select ServerName, WMI-Error, Error
    }
    
}

Write-Host 'EXCHANGE Mailbox SERVERS Check' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green

#DbStatusInfo
foreach ($server in $MailboxExchangeServers){
		Write-host "Checking:  " $server -ForegroundColor Green
        
        $DbStatusExchange = Get-MailboxDatabase -Server $server -Status | where {$_.Name -notlike "*TEST*"} `
                    | Select @{Label = "ServerName"; Expression = {($server)}},`
                        Name,DatabaseSize,AvailableNewMailboxSpace,LastFullBackup | Sort Name  # LastIncrementalBackup
        $DbStatusExchangeResults += $DbStatusExchange 
        
}

################## Generate HTML file ###############

Write-Host "Creating the HTML file at $(Get-date)" -ForegroundColor Green

# OUTPUT
$html = New-HTMLHead

#Exchange
$CPUMemInfoExchangeResultsTable = $CPUMemInfoExchangeResults | New-HTMLTable -SetAlternating $true | Add-HTMLTableColor -ScriptBlock {[double]$args[0] -gt 98} -Column 'MemoryUsage' -AttrValue 'background-color: #FF0000' | Add-HTMLTableColor -ScriptBlock {[double]$args[0] -gt 75} -Column 'CpuUsage' -AttrValue 'background-color: #FF0000' 
$DiskInfoExchangeResultsTable = $DiskInfoExchangeResults | New-HTMLTable -SetAlternating $true | Add-HTMLTableColor -Argument 'True' -Column 'BreachedThresholds' -AttrValue 'background-color: #FF0000'
$DbStatusExchangeResultsTable = $DbStatusExchangeResults | New-HTMLTable -SetAlternating $true | Add-HTMLTableColor -Argument $null -Column 'LastFullBackup' -AttrValue 'background-color: #FF0000' 
$ServicesExchangeResultsTable = $ServicesExchangeResults| New-HTMLTable -SetAlternating $true | Add-HTMLTableColor -Argument 'Stopped' -Column 'Status' -AttrValue 'background-color: #FF0000' 
$dagHealthCheckTable = Get-Content $dagHealthCheck
$EXCErrorWMITable = $ExcErrorWmi | New-HTMLTable -SetAlternating $true | Add-HTMLTableColor -Scriptblock {[string]$args[0] -notlike "*TMG*"} -Column 'ServerName' -AttrValue 'background-color: #FF0000' -WholeRow

#Exchange
$html += $htmlFormatMain
$html += '<h1>Microsoft Exchange Servers</h1>'
$html += '<h2>Exchange CPU and Memory Usage </h2>'
$html += $CPUMemInfoExchangeResultsTable
$html += '<br />'
$html += '<h2>Exchange local disks space info </h2>'
$html += $DiskInfoExchangeResultsTable
$html += '<br />'
$html += '<h2>Exchange Database info </h2>'
$html += $DbStatusExchangeResultsTable
$html += '<br />'
$html += '<h2>Exchange Services Status </h2>'
$html += $ServicesExchangeResultsTable
$html += '<br />'
$html += '<h2>Exchange Servers with WMI erros </h2>'
$html += '<br />'
if ($ExcErrorWmi) {
    $html += $EXCErrorWMITable
    $html += '<br />'
}
$html += $dagHealthCheckTable
$html += '<br />'
$html += $htmlFormatDoubleLine #adaugat din HTMLTable.ps1

# INVOKE OUTPUT FILE
Invoke-Item $htmlOutputFile


$a = "<style>"
$a = $a + "BODY{background-color:peachpuff;}"
$a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$a = $a + "TH{border-width: 1px;padding: 0px;border-style: solid;border-color: black;background-color:thistle}"
$a = $a + "TD{border-width: 1px;padding: 0px;border-style: solid;border-color: black;background-color:PaleGoldenrod}"
$a = $a + "</style>"

Get-Service | sort Status -desc | Select-Object Status, Name, DisplayName | 
ConvertTo-HTML -head $a -body "<H2>Service Information</H2>" | 
Out-File C:\Temp\Test.htm

