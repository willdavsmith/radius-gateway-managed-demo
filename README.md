# Managed routes Gateway demo

This public demo application declares `Radius.Compute/routes`. With no explicit Gateway configuration, the pinned pre-merge Radius workflow installs Gateway API v1.2.1, Contour 0.1.0, GatewayClass `contour`, and the private `radius-system/radius` Gateway.

## Run

The repository expects a Radius Azure GitHub Environment named `azure` that targets the same AKS cluster as the current `kubectl` context.

```shell
./setup.sh setup
```

Until [radius-project/ai-extensions#672](https://github.com/radius-project/ai-extensions/pull/672) merges, do not use the Radius canvas Deploy or Delete buttons: generated workflows use released or `main` templates and do not include the feature under test. Trigger the already-pinned workflows directly:

```shell
gh workflow run run-rad-commands.yml \
  --repo willdavsmith/radius-gateway-managed-demo \
  --ref cleanup-verification \
  -f environment=azure
```

Follow the run in GitHub Actions or with `gh run watch`.

```shell
./setup.sh verify
kubectl get gatewayclass contour
kubectl get gateway radius -n radius-system
kubectl get service -n radius-system -l app.kubernetes.io/component=envoy
```

Expected result: GatewayClass `contour` uses controller `projectcontour.io/gateway-controller`, Gateway `radius-system/radius` is programmed, the Envoy Service is `ClusterIP`, and the application HTTPRoute is attached to the Gateway.

Trigger the pinned delete workflow directly and wait for it to finish:

```shell
run_url="$(
  gh workflow run delete-application.yml \
    --repo willdavsmith/radius-gateway-managed-demo \
    --ref cleanup-verification \
    -f environment=azure \
    -f application=gateway-managed-demo
)"
gh run watch "${run_url##*/}" \
  --repo willdavsmith/radius-gateway-managed-demo \
  --exit-status
```

Due to [radius-project/radius#12878](https://github.com/radius-project/radius/issues/12878), the successful application delete currently leaves the recipe-generated Deployment, Service, and Route objects behind. The managed lifecycle action safely retains the shared Gateway infrastructure while those routes exist.

Run the demo-only workaround:

```shell
./setup.sh teardown
```

`teardown` removes only Deployment, Service, HTTPRoute, TCPRoute, TLSRoute, and UDPRoute objects carrying both `radapp.io/application=gateway-managed-demo` and `radapp.io/environment=azure`. It then dispatches `delete-application.yml` again on `cleanup-verification`, waits for the run with `gh run watch --exit-status`, and verifies that the lifecycle action removed Gateway `radius`, GatewayClass `contour`, Contour, and its owned Gateway API CRDs. It never deletes that managed infrastructure directly.

Set `DEMO_ENVIRONMENT`, `DEMO_REPO`, or `DEMO_WORKFLOW_REF` to override `azure`, `willdavsmith/radius-gateway-managed-demo`, or `cleanup-verification`.

Until PR #672 merges, all first-party extension actions are pinned to its source commit, `radius-project/ai-extensions@246f09f3b6313c705fb38d5ae7276356a5c9aba8`. Workflow commands must use `--ref cleanup-verification`.
