Param (
	[parameter(Mandatory=$false)]
	[string]$VariableName = 'PingMonitorDevices',
    [parameter(Mandatory=$false)]
	[boolean]$Manual = $false
)

$timer =  [system.diagnostics.stopwatch]::StartNew()

# Check is the variable exists. Error if not.
try{
    $DeviceJson = Get-AutomationVariable -Name $VariableName -ErrorAction Stop
} catch {
    Write-Output "Please create an Automation Variable named '$VariableName' before continuing"
    throw "Missing Automation Variable '$VariableName'"
}

$ComputersJson = Get-AutomationVariable -Name $VariableName
$Computers = ConvertFrom-Json $ComputersJson

$order = @($Computers).count
foreach($Computer in $Computers | sort Order){
    # Ping the computer
    $test = Test-Connection -ComputerName $Computer.Name -Count 1 -Quiet
    
    # if no response check the number of minutes since last no response against the threshold
    if($test -eq $false){
        # Check the number of minutes since the last heartbeat against the number of minutes in the Send Threshold
        $MinutesSinceLastHeartbeat = (New-TimeSpan -Start $Computer.LastHeartbeat -End (Get-Date).ToUniversalTime()).TotalMinutes
        if($MinutesSinceLastHeartbeat -gt $Computer.ThresholdMinutes){
            # Check the number of minutes since the last report against the number of minutes supress alerts
            $MinutesSinceLastReport = (New-TimeSpan -Start $Computer.LastReport -End (Get-Date).ToUniversalTime()).TotalMinutes     
            if($MinutesSinceLastReport -gt $Computer.SupressMinutes){
                # Submit failure to Action runbook
                Write-Output "$($Computer.Name) - Invoke Action - $($timer.Elapsed.TotalSeconds)"
                $FailureDateTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
                
                $Computers | Where-Object{$_.Name -eq $Computer.Name} | %{$_.LastReport = $FailureDateTime; $_.Order = 0}
                
                $Properties = @{}
                $Properties.Name = $Computer.Name
                $Properties.LastHeartbeat = $Computer.LastHeartbeat
                $Properties.FailureDateTime = $FailureDateTime
                $Data = $Properties | ConvertTo-Json
                $EventProperties = [pscustomobject]@{Data=$Data}
                $EVENTDATA = [pscustomobject]@{EventProperties=$EventProperties}

                if($Manual -ne $true){
                    Invoke-AutomationWatcherAction -Data $Data
                } else {
                    .\PingMonitor-Action.ps1 -eventData $EVENTDATA
                }
                
                Set-AutomationVariable -Name $VariableName -Value ($Computers | ConvertTo-Json -Compress).ToString()
            } else {
                Write-Output "$($Computer.Name) - Supressed - $($MinutesSinceLastReport)"
            }
        } else {
                Write-Output "$($Computer.Name) - Threshold not meet - $($MinutesSinceLastHeartbeat)"
        }
    } else {
        Write-Output "$($Computer.Name) - Good - $($timer.Elapsed.TotalSeconds)"
        $Computers | Where-Object{$_.Name -eq $Computer.Name} | %{$_.LastHeartbeat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm'); $_.Order = $order}
        Set-AutomationVariable -Name $VariableName -Value ($Computers | ConvertTo-Json -Compress).ToString()
    }
    $order--
}

$timer.Stop()
Write-Output "$('-' * 50) `nTotal Runtime - $($timer.Elapsed.TotalSeconds)"