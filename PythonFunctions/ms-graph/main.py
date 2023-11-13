import asyncio
import configparser
from msgraph.generated.models.o_data_errors.o_data_error import ODataError
from graph import Graph


async def main():
    # Load settings
    config = configparser.ConfigParser()
    config.read(["config.cfg", "config.dev.cfg"])
    azure_settings = config["azure"]

    graph: Graph = Graph(azure_settings)

    choice = -1

    while choice != 0:
        print("Please choose one of the following options:")
        print("0. Exit")
        print("1. Display access token")
        print("2. Invite a guest user")

        try:
            choice = int(input())
        except ValueError:
            choice = -1

        try:
            if choice == 0:
                print("Goodbye...")
            elif choice == 1:
                await display_access_token(graph)
            elif choice == 2:
                await invite_guest_user(graph)
            else:
                print("Invalid choice!\n")
        except ODataError as odata_error:
            print("Error:")
            if odata_error.error:
                print(odata_error.error.code, odata_error.error.message)


async def display_access_token(graph: Graph):
    token = await graph.get_user_token()
    print("User token:", token, "\n")


async def invite_guest_user(graph: Graph):
    response = await graph.invite_guest_user()
    print(response, "\n")


# Run main
asyncio.run(main())
