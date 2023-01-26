# Log in to Azure
az login

# Select Azure subscription
$subscriptionId = Read-Host "Enter your Azure subscription ID"
az account set --subscription $subscriptionId

# Get list of key vault secrets
$vaultName = Read-Host "Enter the name of the key vault"
az keyvault secret list --vault-name $vaultName -o table --query "[].{name:name}"

# Prompt user to select a secret
$secretName = Read-Host "Enter the name of the secret you want to retrieve"

# Retrieve the secret value and copy to clipboard
az keyvault secret show --name $secretName --vault-name $vaultName --query "value" -o tsv | clip
Write-Host "the password was copied to your clipboard"