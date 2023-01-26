# Login to Azure
Connect-AzAccount

# Function to batch upload secrets from an Excel file
Function Add-SecretsFromExcel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName,
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Import the Excel file into a variable
    $secrets = Import-Csv -Path $FilePath

    # Loop through each row of the Excel file
    foreach ($secret in $secrets) {
        $secretName = $secret.Name
        $password = $secret.Password | ConvertTo-SecureString -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $VaultName -Name $secretName -SecretValue $password
    }
}

# Function to export all secrets and passwords from the key vault to an Excel file
Function Export-Secrets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName,
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Get all secrets from key vault
    $secrets = Get-AzKeyVaultSecret -VaultName $VaultName
    $secretsArray = @()

    # Loop through each secret to extract the name and value
    foreach ($secret in $secrets) {
        $secretName = $secret.name
        $keyVaultValue = az keyvault secret show --name $secretName --vault-name $VaultName --query "value" -o tsv

        $secretObject = [PSCustomObject]@{
            "Name" = $secretName
            "Password" = $keyVaultValue

        }
        $secretsArray += $secretObject
    }

    # Export the secrets array to Excel file
    $secretsArray | Export-Csv -Path $FilePath -NoTypeInformation
}

# Main script
$vaultName = Read-Host "Enter the name of the Azure Key Vault"
$subscriptionId = Read-Host "Enter the SubscriptionID of the Azure Key Vault"

az account set --subscription $subscriptionId

$action = Read-Host "What do you want to do - Upload secrets/Export secrets ? (Enter UP/EX)"

if ($action -eq "UP") {
    $filePath = Read-Host "Enter the file path for the Excel file containing the secrets (e.g. C:\secrets.csv)"
    Add-SecretsFromExcel -VaultName $vaultName -FilePath $filePath
}
elseif ($action -eq "EX") {
    $filePath = Read-Host "Enter the file path to export the secrets (e.g. C:\secrets.csv)"
    Export-Secrets -VaultName $vaultName -FilePath $filePath
}
else {
    Write-Warning "Invalid action selected"
}

