
function Change-RegistryKey {
    param(
        [string]$action,
        [string]$registryPath,
        [string]$registryKey,
        [string]$newValue
        
    )

    try {
        if($action -eq "remove"){
            # remove the registry key
            Remove-ItemProperty -Path $registryPath -Name $registryKey -Force -Verbose
            $message = "Registry key $registryKey was removed"
        }else{
            # Change registry key value
            Set-ItemProperty -Path $registryPath -Name $registryKey -Value $newValue
            $message = "Registry key $registryKey at $registryPath has been updated with new value $newValue"
        }
        # write log to file
        $logFile = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WifiRegKeyChangeLog.txt"
        Add-Content -Path $logFile -Value $message
    } catch {
        #write error message to log file
        $errorMessage = "Error: $($_.Exception.Message)"
        $logFile = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WifiRegKeyChangeLog.txt"
        Add-Content -Path $logFile -Value $errorMessage
    }
}

Change-RegistryKey -action "change" -registryPath "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" -registryKey "EnableActiveProbing" -newValue 1
Change-RegistryKey -action "remove" -registryPath "HKLM:\Software\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" -registryKey "NoActiveProbe" 
Change-RegistryKey -action "remove" -registryPath "HKLM:\Software\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" -registryKey "DisablePassivePolling"


