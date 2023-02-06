# Check if user is already authenticated
if (!(az account show)) {
    az login
}

$subscriptionId = "<enter subscriptionId>"
$vaultName = ""
$secretName = ""
$showOrCopy = ""
$continue = ""

while($continue -ne "q"){
    if ($continue -eq 'q')
{
    Write-Host "Exiting script..."
    break
}

    # Get list of key vault secrets
    while ($vaultName -eq "") {
        Write-Host "Welcome to REIZ TECH Password Manager!"
        Write-Host "Key Vaults that you have access:"
        az keyvault list --query "[].{Name:name}" -o tsv
        Write-Host "`n$line"
        
        $vaultName = Read-Host "Enter the name of the key vault (or type 'q' to quit)"
        if ($vaultName -eq "q") {
            Write-Host "Exiting script..."
            break
        }

        try {
            Write-Host "Availble Secrets:"
            az keyvault secret list --vault-name $vaultName -o tsv --query "[].{name:name}"
            Write-Host "`n$line"
        }
        catch {
            Write-Host "Error: Invalid key vault name. Please try again."
            $vaultName = ""
        }
    }

    if ($vaultName -eq "q") {
        break
    }

    # Prompt user to select a secret
    while ($secretName -eq "") {
        $secretName = Read-Host "Enter the name of the secret you want to retrieve (or type 'q' to quit)"
        if ($secretName -eq "q") {
            Write-Host "Exiting script..."
            break
        }

        try {
            az keyvault secret show --name $secretName --vault-name $vaultName >$null 2>&1
            
        }
        catch {
            Write-Host "Error: Invalid secret name. Please try again."
            $secretName = ""
        }
    }

    if ($secretName -eq "q") {
        break
    }

    # Retrieve the secret value
    while ($showOrCopy -ne "s" -and $showOrCopy -ne "c") {
        $showOrCopy = Read-Host "Do you want to show or copy the password? (Enter 's' to show or 'c' to copy)"
    }

    if ($showOrCopy -eq "s") {
        $secretValue = az keyvault secret show --name $secretName --vault-name $vaultName --query "value" 
        $secretValue = $secretValue -replace '"', ""
        Write-Host "The password: $secretValue"
    }
    else {
        az keyvault secret show --name $secretName --vault-name $vaultName --query "value" -o tsv | clip
        Write-Host "The password was copied to your clipboard."
    }

    $continue = Read-Host "Do you want to run the script again? ('y' for yes or 'q' to quit)"

    if ($continue -eq 'y') {
        $vaultName = ""
        $secretName = ""
        $showOrCopy = ""
    }

}
