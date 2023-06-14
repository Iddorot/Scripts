from azure.identity import AzureCliCredential
from azure.mgmt.resource import ResourceManagementClient

def print_resource_details(resource):
    print("Resource Name: {}".format(resource.name))
    print("Resource ID: {}".format(resource.id))
    print("----------------------------------")

def move_resources(source_subscription_id, source_resource_group_name, destination_subscription_id, destination_resource_group_name):
    credential = AzureCliCredential()
    resource_client = ResourceManagementClient(credential, source_subscription_id)
    destination_resource_group_id = f"/subscriptions/{destination_subscription_id}/resourceGroups/{destination_resource_group_name}"

    resources = [
        resource for resource in resource_client.resources.list_by_resource_group(source_resource_group_name)
    ]

    resource_ids = [resource.id for resource in resources]

    for resource in resources:
        print_resource_details(resource)

    move_resources_result = resource_client.resources.begin_move_resources(
        source_resource_group_name,
        {
            "resources": resource_ids,
            "target_resource_group": destination_resource_group_id
        }
    ).result()

    print("Move resources result: {}".format(move_resources_result))

# Specify the subscription and resource group details
source_subscription_id = ""
source_resource_group_name = ""
destination_subscription_id = ""
destination_resource_group_name = ""

# Move resources
move_resources(source_subscription_id, source_resource_group_name, destination_subscription_id, destination_resource_group_name)


