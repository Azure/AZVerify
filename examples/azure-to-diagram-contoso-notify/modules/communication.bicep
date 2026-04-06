@description('Resource tags.')
param tags object = {}

// Email Service — data location Europe; provides the email sending infrastructure.
resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: 'contoso-email-service'
  location: 'global'
  tags: tags
  properties: {
    dataLocation: 'Europe'
  }
}

// Custom domain — CustomerManaged, requires DNS verification before use.
// Required DNS records are detailed in dependencies/README.md.
// Current verification status: Domain TXT record failed (DnsRecordsNotMatched).
resource emailDomain 'Microsoft.Communication/emailServices/domains@2023-06-01-preview' = {
  parent: emailService
  name: '<DOMAIN>'
  location: 'global'
  properties: {
    domainManagement: 'CustomerManaged'
    userEngagementTracking: 'Disabled'
  }
}

// ACS Communication Service — linked to the custom domain.
// NOTE: Domain must be DNS-verified before ACS can send from <DOMAIN>.
// After verification, update senderEmail in Contoso-Notify.bicepparam.
resource acs 'Microsoft.Communication/CommunicationServices@2023-04-01' = {
  name: 'Contoso-notify-ACS'
  location: 'global'
  tags: tags
  properties: {
    dataLocation: 'Europe'
    linkedDomains: [
      emailDomain.id
    ]
  }
}

output acsId string = acs.id
output emailServiceId string = emailService.id
output emailDomainId string = emailDomain.id
