from configparser import SectionProxy
from azure.identity import InteractiveBrowserCredential
from msgraph import GraphServiceClient
import httpx


class Graph:
    settings: SectionProxy
    client_secret_credential: InteractiveBrowserCredential 
    user_client: GraphServiceClient

    def __init__(self, config: SectionProxy):
        self.settings = config
        tenant_id = self.settings["tenantId"]
        graph_scopes = self.settings["graphUserScopes"].split(" ")

        # Using InteractiveBrowserCredential to authenticate with user interaction
        self.client_secret_credential = InteractiveBrowserCredential(
            tenant_id=tenant_id,
        )


    async def get_user_token(self):
        graph_scopes = self.settings["graphUserScopes"]
        access_token = self.client_secret_credential.get_token(graph_scopes)
        return access_token.token

    async def invite_guest_user(self):
        token = await self.get_user_token()
        invitedUserEmailAddress = self.settings["invitedUserEmailAddress"]
        invitedUserId = self.settings["invitedUserId"]
        ccName = self.settings["ccName"]
        ccAddress = self.settings["ccAddress"]

        graph_url = "https://graph.microsoft.com/v1.0/invitations"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
        request_body = {
            "invitedUserEmailAddress": f"{invitedUserEmailAddress}",
            "sendInvitationMessage": True,
            "invitedUserMessageInfo": {
                "messageLanguage": "en-US",
                "ccRecipients": [
                    {
                        "emailAddress": {
                            "name": f"{ccName}",
                            "address": f"{ccAddress}",
                        }
                    }
                ],
            },
            "inviteRedirectUrl": "https://myapps.microsoft.com?tenantId=",
            "invitedUser": {"id": f"{invitedUserId}"},
            "resetRedemption": True,
        }
        async with httpx.AsyncClient() as client:
            response = await client.post(graph_url, headers=headers, json=request_body)
            return response.status_code, response.text
