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
    codeReference: '.github/workflows/run-rad-commands-azure.yml#L356'
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

resource gatewayManagedDemoImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'gateway-managed-demo-image'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: 'Dockerfile#L1'
    build: {
      source: 'git::https://github.com/willdavsmith/radius-gateway-managed-demo.git?ref=ef3b6df3368b8c576d154d50fc312f0db1676c60'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource gatewayManagedDemoContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'gateway-managed-demo'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: '.radius/app.bicep#L50'
    containers: {
      gatewayManagedDemo: {
        image: gatewayManagedDemoImage.properties.imageReference
        ports: {
          web: {
            containerPort: 80
          }
        }
      }
    }
  }
}

resource gatewayManagedDemoRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'gateway-managed-demo'
  properties: {
    environment: environment
    application: gatewayManagedDemoApp.id
    codeReference: 'README.md#L3'
    kind: 'HTTP'
    rules: [
      {
        matches: [
          {
            httpPath: '/'
          }
        ]
        destinationContainer: {
          resourceId: gatewayManagedDemoContainer.id
          containerName: 'gatewayManagedDemo'
          containerPort: 80
        }
      }
    ]
  }
}
