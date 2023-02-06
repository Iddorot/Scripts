$OfficeAppsNames = @(("Word.lnk","Word"), ("PowerPoint.lnk", "PowerPoint"), ("Outlook.lnk","Outlook"))

function Create-Shortcut ([string]$Path,[array]$AppName)
{
    $LocationName = $AppName[0]
    $ShortcutName = $AppName[1]
    $TargetFile ="$Path\$LocationName"
    $ShortcutFile = "$env:Public\Desktop\$ShortcutName.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    try
    {
        if (-not (Test-Path $ShortcutFile))
        {
            $Shortcut.Save()
            Write-Output "$ShortcutName was created successfully."
        }
        else
        {
            Write-Output "$ShortcutName already exists."
        }
    }
    catch
    {
        Write-Output "Error: $ShortcutName was not created."
        Write-Output $_
    }
}

# Define the Create-OfficeShortCuts function
function Create-OfficeShortCuts ([array]$OfficeAppsNames)
{
    foreach($OfficeAppName in $OfficeAppsNames)
    {
        $TargetOfficePath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
        Create-Shortcut -Path $TargetOfficePath -AppName $OfficeAppName
    }
}

# Create the log file
$LogFile = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DesktopShortcutLogs.txt"
if (!(Test-Path $LogFile))
{
    New-Item $LogFile -ItemType File
}

# Create the Office shortcuts
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Starting script Create Office Shortcuts" | Out-File $LogFile -Append
Write-Output "Current user: $(whoami)" | Out-File $LogFile -Append
Create-OfficeShortCuts -OfficeAppsNames $OfficeAppsNames | Out-File $LogFile -Append

# Create the Teams shortcut
$TeamsPath = "C:\Users\$env:UserName\AppData\Local\Microsoft\Teams"
Create-Shortcut -Path $TeamsPath -AppName ("Update.exe", "Microsoft Teams") | Out-File $LogFile -Append

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Finish running the script  Create Office Shortcuts" | Out-File $LogFile -Append

