# Original Architecture Request

> Sketch of an Azure architecture with the following components:
> - ResourceGroup 01 as the outer boundary
> - VNET-01 containing Subnet-01 and Subnet-02
> - VM01 connected to NIC-01 inside Subnet-01
> - Webapp connected via Private Link to Subnet-02 (Private Endpoint)
> - App-Service (App Service Plan) as dependency for Webapp
