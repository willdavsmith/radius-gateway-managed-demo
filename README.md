# Managed routes Gateway demo

This public demo application declares `Radius.Compute/routes`. With no explicit Gateway configuration, the pinned pre-merge Radius workflow installs Gateway API v1.2.1, Contour 0.1.0, GatewayClass `contour`, and the private `radius-system/radius` Gateway.

## Run

The repository expects a Radius Azure GitHub Environment named `azure` that targets the same AKS cluster as the current `kubectl` context.

```shell
./setup.sh setup
```

Open the repository in the GitHub Copilot app and deploy the root `.radius/app.bicep` with environment `azure`.

```shell
./setup.sh verify
kubectl get gatewayclass contour
kubectl get gateway radius -n radius-system
kubectl get service -n radius-system -l app.kubernetes.io/component=envoy
```

Expected result: GatewayClass `contour` is accepted, Gateway `radius-system/radius` is programmed, the Envoy Service is `ClusterIP`, and the application HTTPRoute is accepted.

Delete `gateway-managed-demo` in the Radius canvas, wait for the delete workflow, then run:

```shell
./setup.sh teardown
```

Until `radius-project/radius#12854` merges, the workflows pin Radius actions to commit `000e3749e3b072b75eb6a46ae171688e417bfb5c`.
