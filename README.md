# Managed routes Gateway demo

This public demo application declares `Radius.Compute/routes`. With no explicit Gateway configuration, the pinned pre-merge Radius workflow installs Gateway API v1.2.1, Contour 0.1.0, GatewayClass `contour`, and the private `radius-system/radius` Gateway.

## Run

The repository expects a Radius Azure GitHub Environment named `azure` that targets the same AKS cluster as the current `kubectl` context.

```shell
./setup.sh setup
```

Until `radius-project/radius#12854` merges, do not use the Radius canvas Deploy button: the current canvas regenerates the provider workflow from `main` and removes the feature-under-test. Trigger the already-pinned workflow directly:

```shell
gh workflow run run-rad-commands.yml \
  --repo willdavsmith/radius-gateway-managed-demo \
  -f environment=azure
```

Follow the run in GitHub Actions or with `gh run watch`.

```shell
./setup.sh verify
kubectl get gatewayclass contour
kubectl get gateway radius -n radius-system
kubectl get service -n radius-system -l app.kubernetes.io/component=envoy
```

Expected result: GatewayClass `contour` is accepted, Gateway `radius-system/radius` is programmed, the Envoy Service is `ClusterIP`, and the application HTTPRoute is accepted.

Trigger the pinned delete workflow directly, wait for it to finish, then run:

```shell
gh workflow run delete-application.yml \
  --repo willdavsmith/radius-gateway-managed-demo \
  -f environment=azure \
  -f application=gateway-managed-demo

./setup.sh teardown
```

Until `radius-project/radius#12854` merges, the workflows pin Radius actions to commit `000e3749e3b072b75eb6a46ae171688e417bfb5c`.
