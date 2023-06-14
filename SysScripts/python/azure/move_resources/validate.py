from azure.identity import AzureCliCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.core.exceptions import HttpResponseError

def print_resource_details(resource):
    print("Resource Name: {}".format(resource.name))
    print("Resource ID: {}".format(resource.id))
    print("----------------------------------")

def validate_move_resources(source_subscription_id, source_resource_group_name, destination_subscription_id, destination_resource_group_name):
    credential = AzureCliCredential()
    resource_client = ResourceManagementClient(credential, source_subscription_id)
    destination_resource_group_id = f"/subscriptions/{destination_subscription_id}/resourceGroups/{destination_resource_group_name}"

    resources = [
        resource for resource in resource_client.resources.list_by_resource_group(source_resource_group_name)
    ]

    for resource in resources:
        try:
            print_resource_details(resource)

            resource_id = resource.id

            validate_move_resources_result = resource_client.resources.begin_validate_move_resources(
                source_resource_group_name,
                {
                    "resources": [resource_id],
                    "target_resource_group": destination_resource_group_id
                }
            ).result()

            print("Validate move resources result: {}".format(validate_move_resources_result))
            print("----------------------------------")
        except HttpResponseError as e:
            print("Error occurred: {}".format(e))
            print("----------------------------------")
            continue

# Specify the subscription and resource group details
source_subscription_id = ""
source_resource_group_name = ""
destination_subscription_id = ""
destination_resource_group_name = ""

# Validate move resources
validate_move_resources(source_subscription_id, source_resource_group_name, destination_subscription_id, destination_resource_group_name)
