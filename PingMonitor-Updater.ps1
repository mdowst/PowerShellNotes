Param (
	[parameter(Mandatory=$true)]
	[string]$Device,
    [parameter(Mandatory=$false)]
	[string]$VariableName = 'PingMonitorDevices',
    [Parameter(Mandatory=$false)]
	[int]$ThresholdMinutes = 5,
	[Parameter(Mandatory=$false)]
	[int]$SupressMinutes = 15,
	[parameter(Mandatory=$false)]
	[boolean]$Delete = $false,
    [parameter(Mandatory=$false)]
	[boolean]$TestTime = $true
)

# Check is the variable exists. Error if not.
try{
    $DeviceJson = Get-AutomationVariable -Name $VariableName -ErrorAction Stop
} catch {
    Write-Output "Please create an Automation Variable named '$VariableName' before continuing"
    throw "Missing Automation Variable '$VariableName'"
}

[System.Collections.Generic.List[PSObject]] $Computers = @()

try{
    $Devices = $DeviceJson | ConvertFrom-Json -ErrorAction Stop
    $Devices | Where-Object{$_.Name -ne $null} | Foreach-Object{$Computers.Add($_)}
} catch {
    Write-Output "Unable to parse JSON. The variable will be recreated."
    Write-Output $DeviceJson
}

if($Delete -eq $true){
    $Computers = $Computers | Where-Object {$_.Name -ne $Device}
} else {
    if($Computers | Where-Object {$_.Name -eq $Device}) {
        $Computers = $Computers | Where-Object {$_.Name -ne $Device}
    }
    [pscustomobject]$Computer = @{
        Name = $Device
        LastReport = [DateTime]::MinValue.ToString('yyyy-MM-dd HH:mm')
        ThresholdMinutes = $ThresholdMinutes
        SupressMinutes = $SupressMinutes
        LastHeartbeat = (get-date).ToString('yyyy-MM-dd HH:mm')
        Order = 1
    }
    $Computers.Add($Computer)
}

Set-AutomationVariable -Name $VariableName -Value ($Computers | ConvertTo-Json -Compress).ToString()

Write-Output ($Computers | ConvertTo-Json).ToString()

if($TestTime -eq $true){
    $timer =  [system.diagnostics.stopwatch]::StartNew()
    $order = @($Computers).count
    foreach($Computer in $Computers | sort Order){
        # Ping the computer
        $test = Test-Connection -ComputerName $Computer.Name -Count 1 -Quiet
        
        # if no response check the number of minutes since last no response against the threshold
        if($test -eq $false){
            $MinutesSinceLastReport = (New-TimeSpan -Start $Computer.LastReport -End (Get-Date).ToUniversalTime()).TotalMinutes
            if($MinutesSinceLastReport -gt $Computer.SupressMinutes){
                Write-Output "$($Computer.Name) - Invoke-Action - $($timer.Elapsed.TotalSeconds)"
            } else {
                Write-Output "$($Computer.Name) - Supressed - $($timer.Elapsed.TotalSeconds)"
            }
        } else {
            Write-Output "$($Computer.Name) - Good - $($timer.Elapsed.TotalSeconds)"
        }
        $order--
    }

    $timer.Stop()
    Write-Output "$('-' * 50) `nTotal Runtime - $($timer.Elapsed.TotalSeconds)"
}