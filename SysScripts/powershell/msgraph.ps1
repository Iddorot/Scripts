Connect-MgGraph -Scopes "User.ReadWrite.All" -TenantId <tenantID>
$user = Get-MgUser -Filter "startsWith(mail, 'vuser@email')"
New-MgInvitation `
    -InvitedUserEmailAddress $user.Mail `
    -InviteRedirectUrl "https://myapps.microsoft.com" `
    -ResetRedemption `
    -SendInvitationMessage `
    -InvitedUser $user