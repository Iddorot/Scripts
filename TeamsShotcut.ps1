Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process

function Create-Shortcut ([string]$Path,[array]$AppName)

{
            $LocationName = $AppName[0]
            $ShortcutName = $AppName[1]
            $TargetFile ="$Path\$LocationName"
            $ShortcutFile = "$env:Public\Desktop\$ShortcutName.lnk"
            $WScriptShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
            $Shortcut.TargetPath = $TargetFile
            If ($ShortcutName ="Teams"){
                $Shortcut.Arguments = '--processStart Teams.exe'
            }

            try
            {
                $Shortcut.Save()
                Write-Output "$ShortcutName was created successfully."
            }
            catch
            {
                Write-Output "ShortcutName was not created"
                Write-Output $_
            }
            
}

Create-Shortcut -Path "C:\Users\$env:UserName\AppData\Local\Microsoft\Teams" -AppName ("Update.exe", "Microsoft Teams")
