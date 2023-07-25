from datetime import datetime
import logging
import pytz
import azure.functions as func
from azure.identity import ClientSecretCredential
from msgraph.core import GraphClient
import os
from exchangelib import (
    Configuration,
    OAuth2Credentials,
    Identity,
    Account,
    Message,
    Mailbox,
    HTMLBody,
)
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from requests_oauthlib import OAuth2Session
import requests
from oauthlib.oauth2 import BackendApplicationClient
from requests_oauthlib import OAuth2Session



def get_kv_secret(secret_name):
    try:
        keyvault_url = os.environ["AZURE_KEYVAULT_RESOURCEENDPOINT"]
        client = SecretClient(
            vault_url=keyvault_url, credential=DefaultAzureCredential()
        )
        return client.get_secret(secret_name).value
    except Exception as e:
        logging.error(f"FAIL get_kv_secret: {e}")
        raise e


# create ews credantials
def ews_credentials():
    try:
        credentials = OAuth2Credentials(
            client_id=get_kv_secret("ews-client-id"),
            client_secret=get_kv_secret("ews-client-secret"),
            tenant_id=get_kv_secret("tenant-id"),
            identity=Identity(primary_smtp_address="<primary_smtp_address>"),
        )
        config = Configuration(
            service_endpoint="https://outlook.office365.com/EWS/Exchange.asmx",
            credentials=credentials,
            auth_type="OAuth 2.0",
        )
        ews_account = Account(
            primary_smtp_address="<primary_smtp_address>", config=config, autodiscover=False
        )
        return ews_account
    except Exception as e:
        logging.error(f"Error occurred in ews_credentials(): {e}")
        raise


# Send email notification
def send_email_notification(ews_account, html_body,to_recipient, subject):
    try:
        m = Message(
            account=ews_account,
            folder=ews_account.sent,
            subject=subject,
            body=HTMLBody(html_body),
            to_recipients=[
                Mailbox(email_address=to_recipient),
            ],
        )
        m.send_and_save()
        ews_account.protocol.close()
        logging.info("email was send")

    except Exception as e:
        logging.info(f"Error occurred in send_email_notification : {e}")
        raise



def is_within_one_week(expiration_date):
    try:
        expiration_datetime = datetime.fromisoformat(expiration_date[:-1])
        time_difference = expiration_datetime - datetime.now()
        return time_difference.total_seconds() <= 7 * 24 * 60 * 60
    except ValueError:
        return False
    

def compose_email(app_id, app_name, password_expire, reason):
    html_template = """
    <html>
    <body>
        <h2>App Information:</h2>
        <p><strong>App_ID:</strong> {app_id}</p>
        <p><strong>App_Display_Name:</strong> {app_name}</p>
        <p><strong>Password_Expires:</strong> {password_expire}</p>
    </body>
    </html>
    """
    email_body = html_template.format(app_id=app_id, app_name=app_name, password_expire=password_expire)
    ews_account = ews_credentials()
    subject = "App registration Secret Expiring Soon"
    
    if reason == "name1 or name1":
        to_recipient = "<to@recipient>"
    elif reason == "name2":
        to_recipient = "<to@recipient>"
    elif reason == "name3":
        to_recipient = "<to@recipient>"

    send_email_notification(ews_account, email_body,to_recipient, subject)

def get_access_token():
    tenant_id = get_kv_secret("tenant-id")
    client_secret = get_kv_secret("graph-api-client-secret")
    client_id = get_kv_secret("graph-api-client-id")
    scope = 'https://graph.microsoft.com/.default'
    token_url = f'https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token'

    client = BackendApplicationClient(client_id=client_id)
    oauth = OAuth2Session(client=client)
    token = oauth.fetch_token(
        token_url=token_url,
        client_id=client_id,
        client_secret=client_secret,
        scope=scope 
    )

    return token['access_token']

def get_app_registration_dict():
    try:
        access_token = get_access_token()
        headers = {'Authorization': f'Bearer {access_token}'}
        response = requests.get("https://graph.microsoft.com/v1.0/applications?$select=id,displayName,passwordCredentials", headers=headers)

        return response.json()

    except Exception as e:
        logging.info(f"Error occurred in get_app_registration_dict: {e}")
        raise



def main(mytimer: func.TimerRequest) -> None:
    logging.getLogger().setLevel(logging.INFO)
    vln_timestamp = datetime.now(pytz.timezone("Europe/Vilnius")).isoformat()

    try:
        app_dict = get_app_registration_dict()

        for app in app_dict['value']:
            
            app_name = app['displayName'].lower()
            app_id = app['id']
            password_credentials = app.get('passwordCredentials', [])

            for cred in password_credentials:
                password_expire = cred['endDateTime']
                if is_within_one_week(password_expire):
                    if "<name1>" in app_name or "name1" in app_name:
                        compose_email(app_id, app_name, password_expire, "name1 or name1")
                    elif "name2" in app_name:
                        compose_email(app_id, app_name, password_expire, "name2")
                    elif "name3" in app_name:
                        compose_email(app_id, app_name, password_expire, "name3")

        logging.info("Python timer trigger function ran at %s", vln_timestamp)

    except Exception as e:
        logging.info(f"Failed to execute main function: {e}")
        raise e

