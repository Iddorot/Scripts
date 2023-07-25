<h1 align="center">App Registration Secret Expiration Notifier</h1>

<h2>Introduction</h2>
<p>This is a Python Timer Trigger function designed to run on Microsoft Azure Functions. It checks the expiration date of password credentials for registered applications in Azure Active Directory (AAD) and sends email notifications when the expiration date is within one week. The function uses various Azure services, including Azure Key Vault, Microsoft Graph API, and Exchange Web Services (EWS), to accomplish its tasks.</p>

<h2>Infrastructure Setup</h2>
<p>Before deploying and running this function, you need to set up the following components:</p>
<ol>
  <li><strong>Azure Key Vault</strong>: Create an Azure Key Vault to store sensitive information, such as client secrets, tenant IDs, etc. The function will use this vault to access credentials securely.</li>
  <li><strong>Azure Active Directory Application Registration</strong>: Register an application in Azure AD with appropriate permissions to access the Microsoft Graph API. Obtain the Client ID, Client Secret, and Tenant ID of this registered application. The application should have the necessary API permissions to read applications and send emails on behalf of users.</li>
  <li><strong>Exchange Web Services (EWS) Account</strong>: Create an Exchange Web Services (EWS) account that will be used to send email notifications. The account should have the necessary permissions to send emails. with Application Impersonation role assigned to it</li>
  <li><strong>Azure Function</strong>: Set up an Azure Function in your Azure subscription. The function should be configured to use Python runtime.</li>
  <li><strong>Secrets Configuration</strong>: Store the necessary secrets in the Azure Key Vault, including the credentials for accessing the Graph API and EWS, as well as any other configuration details.</li>
</ol>

<h2>Function Explanation</h2>
<p>The function consists of several components that work together to check and notify about expiring secrets.</p>
<ol>
  <li><strong>Get Key Vault Secrets</strong>: The <code>get_kv_secret</code> function retrieves a secret value from the Azure Key Vault using the <code>DefaultAzureCredential</code>.</li>
  <li><strong>EWS Credentials</strong>: The <code>ews_credentials</code> function creates OAuth2 credentials for Exchange Web Services (EWS). It obtains the client ID, client secret, and tenant ID from the Key Vault to authenticate and access the EWS account.</li>
  <li><strong>Send Email Notification</strong>: The <code>send_email_notification</code> function sends an email using the EWS account to the specified recipient with the given subject and HTML body.</li>
  <li><strong>Check if Within One Week</strong>: The <code>is_within_one_week</code> function takes an expiration date as input, checks if it's within one week from the current date, and returns a boolean value accordingly.</li>
  <li><strong>Compose Email</strong>: The <code>compose_email</code> function takes application information, such as app ID, app name, and password expiration date, and composes an HTML email body. It then calls the <code>send_email_notification</code> function to send the notification email based on the reason for the notification (e.g., "skillit or sais," "birthday," or "reminder").</li>
  <li><strong>Get Access Token</strong>: The <code>get_access_token</code> function obtains an access token using the registered Azure AD application's client ID and client secret. It fetches the token to authenticate API requests to the Microsoft Graph API.</li>
  <li><strong>Get App Registration Dictionary</strong>: The <code>get_app_registration_dict</code> function retrieves information about all registered applications in Azure AD using the Microsoft Graph API. It filters out relevant data, including app ID, app display name, and password credentials.</li>
  <li><strong>Main Function</strong>: The <code>main</code> function is the entry point of the Timer Trigger. It gets the current timestamp, calls <code>get_app_registration_dict</code> to fetch information about registered applications, and then iterates through each app's password credentials to check for expiration. If a credential is about to expire within one week, it composes an email and sends it using the EWS account.</li>
</ol>

<h2>Readme</h2>
<p>Before deploying and running the function, ensure that you have completed the Infrastructure Setup section above. Replace all specific names, such as email addresses, application names, etc., with generic placeholders in the code to make it more general. Also, provide appropriate instructions in the readme regarding environment variables and key vault secret names.</p>

<p><strong>Note</strong>: The provided code assumes that you have already set up and configured the required Azure services (Azure Key Vault, Azure Function, etc.) with the appropriate permissions and configurations. Additionally, you should handle error scenarios and potential exceptions more robustly in a production environment.</p>

<p>Please refer to the Azure documentation for detailed guidance on setting up Azure services and configuring Azure Functions.</p>
