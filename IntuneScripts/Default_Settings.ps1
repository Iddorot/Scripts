function Set-AutoTimeZone{
   Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate -Name Start -Value "3"
}

function Remove-MailApp{
    Write-Output "Removing Windows 10 Mail Appx Package"

    if(Get-AppxPackage -Name Microsoft.windowscommunicationsapps -AllUsers){
        Get-AppxPackage -Name Microsoft.windowscommunicationsapps -AllUsers | Remove-AppxPackage -AllUsers -Verbose -ErrorAction Continue
    }
    else {
        Write-Output "Mail app is not installed for any user"
    }

    if(Get-ProvisionedAppxPackage -Online | Where-Object {$_.DisplayName -match "Microsoft.windowscommunicationsapps"}){
        Get-ProvisionedAppxPackage -Online | Where-Object {$_.DisplayName -match "Microsoft.windowscommunicationsapps"} | Remove-AppxProvisionedPackage -Online -AllUsers -Verbose -ErrorAction Continue
    }
    else {
        Write-Output "Mail app is not installed for the system"
}
}

function Remove-PersonalTeams{
If ($null -eq (Get-AppxPackage -Name MicrosoftTeams -AllUsers)) {
    Write-Output “Microsoft Teams Personal App not present”
}
Else {
    Try {
        Write-Output “Removing Microsoft Teams Personal App”
        Get-AppxPackage -Name MicrosoftTeams -AllUsers | Remove-AppPackage -AllUsers
    }
    catch {
        Write-Output “Error removing Microsoft Teams Personal App”
    }
}}

function Rename-Drive{
    Set-Volume -DriveLetter C -NewFileSystemLabel "Reiz Tech"
}

Set-AutoTimeZone
Remove-MailApp
Remove-PersonalTeams
Rename-Drive
