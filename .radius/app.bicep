extension radius

param environment string

@secure()
param registryPassword string

@secure()
param registryUsername string

resource gatewayManagedDemoApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'gateway-managed-demo'
  properties: {
    environment: environment
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: '.radius/app.bicep'
    data: {
      password: {
        value: registryPassword
      }
      username: {
        value: registryUsername
      }
    }
  }
}

resource webImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'web-image'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: 'Dockerfile'
    build: {
      source: 'git::https://github.com/willdavsmith/radius-gateway-managed-demo.git?ref=c1cd1bda9afbb1a6cd8ac8191827d381dc4cca35'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource webContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'web'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: 'index.html'
    containers: {
      web: {
        image: webImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
  }
}

resource webRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'web'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: '.radius/app.bicep'
    kind: 'HTTP'
    rules: [
      {
        matches: [
          {
            httpPath: '/'
          }
        ]
        destinationContainer: {
          resourceId: webContainer.id
          containerName: 'web'
          containerPort: 80
        }
      }
    ]
  }
}
