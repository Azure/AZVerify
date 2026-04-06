# Original Architecture Request

> I need a secure web application with a WAF. An Application Gateway (WAF_v2 SKU) sits in a
> dedicated subnet and routes traffic to an App Service. The App Service uses VNet
> Integration and connects to an Azure SQL Database via Private Endpoint. A Key Vault stores
> the SQL connection string and the App Gateway's SSL certificate. Application Insights
> monitors the App Service. A DNS Zone holds the public DNS record pointing to the App
> Gateway's public IP. Resource group: "rg-secure-webapp".
