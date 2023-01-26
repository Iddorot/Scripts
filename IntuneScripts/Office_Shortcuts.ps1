Write-Host "Starting script Create Office Shortcuts"
Write-Host "Current user: $(whoami)"

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process

$OfficeAppsNames = ("Word.lnk","Word"), ("PowerPoint.lnk", "PowerPoint"), ("Outlook.lnk","Outlook")

function Create-Shortcut ([string]$Path,[array]$AppName)

{
            $LocationName = $AppName[0]
            $ShortcutName = $AppName[1]
            $TargetFile ="$Path\$LocationName"
            $ShortcutFile = "$env:Public\Desktop\$ShortcutName.lnk"
            $WScriptShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
            $Shortcut.TargetPath = $TargetFile
            $Shortcut.Save()
}

function Create-OfficeShortCuts ([array]$OfficeAppsNames){
    foreach($OfficeAppName in $OfficeAppsNames)
        {
            $TargetOfficePath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
            Create-Shortcut -Path $TargetOfficePath -AppName $OfficeAppName
        }
}

Create-OfficeShortCuts -OfficeAppsNames $OfficeAppsNames

Write-Host "Finish running the script  Create Office Shortcuts"