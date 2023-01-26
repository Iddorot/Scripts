
function Change-RegistryKey {
    param(
        [string]$registryPath,
        [string]$registryKey,
        [int]$newValue
    )

    try {
        if( (Get-ItemProperty -Path $registryPath -Name $registryKey) -eq $null ){
            # Create new registry key
            New-ItemProperty -Path $registryPath -Name $registryKey -PropertyType DWORD -Value $newValue -Force
            $message = "Registry key $registryKey created at $registryPath with value $newValue"
        }else{
            # Change registry key value
            Set-ItemProperty -Path $registryPath -Name $registryKey -Value $newValue
            $message = "Registry key $registryKey at $registryPath has been updated with new value $newValue"
        }
        # write log to file
        $logFile = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WifiActionNeededLog.txt"
        Add-Content -Path $logFile -Value $message
    } catch {
        #write error message to log file
        $errorMessage = "Error: $($_.Exception.Message)"
        $logFile = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WifiActionNeededLog.txt"
        Add-Content -Path $logFile -Value $errorMessage
    }
}

Change-RegistryKey -registryPath "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" -registryKey "EnableActiveProbing" -newValue 0
Change-RegistryKey -registryPath "HKLM:\Software\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" -registryKey "NoActiveProbe" -newValue 1
Change-RegistryKey -registryPath "HKLM:\Software\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" -registryKey "DisablePassivePolling" -newValue 1
