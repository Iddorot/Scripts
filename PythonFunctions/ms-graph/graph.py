# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# <UserAuthConfigSnippet>
from configparser import SectionProxy
from azure.identity import ClientSecretCredential
from msgraph import GraphServiceClient
from msgraph.generated.users.item.user_item_request_builder import UserItemRequestBuilder
from msgraph.generated.users.item.mail_folders.item.messages.messages_request_builder import (
    MessagesRequestBuilder)
from msgraph.generated.users.item.send_mail.send_mail_post_request_body import (
    SendMailPostRequestBody)
from msgraph.generated.models.message import Message
from msgraph.generated.models.item_body import ItemBody
from msgraph.generated.models.body_type import BodyType
from msgraph.generated.models.recipient import Recipient
from msgraph.generated.models.email_address import EmailAddress

class Graph:
    settings: SectionProxy
    client_secret_credential: ClientSecretCredential
    user_client: GraphServiceClient

    def __init__(self, config: SectionProxy):
        self.settings = config
        client_id = self.settings['clientId']
        tenant_id = self.settings['tenantId']
        client_secret = self.settings['clientSecret']
        graph_scopes = self.settings['graphUserScopes'].split(' ')

        self.client_secret_credential = ClientSecretCredential(tenant_id, client_id, client_secret)
        self.user_client = GraphServiceClient(self.client_secret_credential, graph_scopes)

    async def get_user_token(self):
        # Assuming you want to obtain the token for a specific scope
        graph_scopes = self.settings['graphUserScopes']
        access_token = self.client_secret_credential.get_token(graph_scopes)
        return access_token.token

    # </GetUserTokenSnippet>

    # <GetUserSnippet>
    async def get_user(self):
        # Only request specific properties using $select
        query_params = UserItemRequestBuilder.UserItemRequestBuilderGetQueryParameters(
            select=['displayName', 'mail', 'userPrincipalName']
        )

        request_config = UserItemRequestBuilder.UserItemRequestBuilderGetRequestConfiguration(
            query_parameters=query_params
        )

        user = await self.user_client.me.get(request_configuration=request_config)
        return user
    # </GetUserSnippet>



    # <MakeGraphCallSnippet>
    async def make_graph_call(self):
        # INSERT YOUR CODE HERE
        return
    # </MakeGraphCallSnippet>