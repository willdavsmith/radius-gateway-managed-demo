#!/usr/bin/env bash

set -euo pipefail

readonly REPO="${DEMO_REPO:-willdavsmith/radius-gateway-managed-demo}"
readonly ENVIRONMENT="${DEMO_ENVIRONMENT:-azure}"
readonly ACTION="${1:-help}"

require_tools() {
    local tool
    for tool in gh kubectl helm jq; do
        command -v "${tool}" >/dev/null 2>&1 || {
            echo "error: ${tool} is required" >&2
            exit 1
        }
    done
}

require_target() {
    [[ -n "${REPO}" ]] || {
        echo "error: set DEMO_REPO or pass owner/repo as argument 2" >&2
        exit 1
    }
    [[ -n "${ENVIRONMENT}" ]] || {
        echo "error: set DEMO_ENVIRONMENT or pass the GitHub Environment as argument 3" >&2
        exit 1
    }
}

require_github_environment() {
    if ! gh api "repos/${REPO}/environments/${ENVIRONMENT}" >/dev/null 2>&1; then
        echo "error: GitHub Environment '${ENVIRONMENT}' does not exist in ${REPO}" >&2
        echo "create and verify it in Radius → Environments → Create environment → Azure, then rerun setup" >&2
        exit 1
    fi
}

delete_environment_variable() {
    local name="$1"
    local variables
    variables="$(
        gh variable list --repo "${REPO}" --env "${ENVIRONMENT}" \
            --json name --jq '.[].name'
    )" || {
        echo "error: failed to read variables from GitHub Environment '${ENVIRONMENT}'" >&2
        exit 1
    }
    if grep -Fxq "${name}" <<<"${variables}"; then
        gh variable delete "${name}" --repo "${REPO}" --env "${ENVIRONMENT}"
    fi
}

managed_gateway_exists() {
    kubectl get gateway radius -n radius-system >/dev/null 2>&1
}

managed_contour_exists() {
    helm status contour -n radius-system >/dev/null 2>&1
}

verify_http_route() {
    local attempt
    local routes
    for ((attempt = 1; attempt <= 24; attempt++)); do
        routes="$(
            kubectl get httproute -A \
                -l radapp.io/application=gateway-managed-demo -o json
        )"
        if jq -e '
          .items | length == 1 and
          all(.[];
            any(.spec.parentRefs[]?;
              .name == "radius" and .namespace == "radius-system") and
            any(.status.parents[]?.conditions[]?;
              .type == "Accepted" and .status == "True") and
            any(.status.parents[]?.conditions[]?;
              .type == "ResolvedRefs" and .status == "True"))
        ' <<<"${routes}" >/dev/null; then
            echo "verified: app HTTPRoute is accepted by radius-system/radius"
            return 0
        fi
        sleep 5
    done
    echo "error: app HTTPRoute was not accepted by radius-system/radius" >&2
    return 1
}

verify_deployed() {
    helm status contour -n radius-system >/dev/null
    kubectl get gatewayclass contour >/dev/null
    kubectl wait --for=condition=Accepted gatewayclass/contour --timeout=2m
    kubectl get gateway radius -n radius-system >/dev/null
    kubectl wait --for=condition=Programmed gateway/radius \
        -n radius-system --timeout=2m
    local service_type
    service_type="$(
        kubectl get service -n radius-system \
            -l app.kubernetes.io/component=envoy \
            -o jsonpath='{.items[0].spec.type}'
    )"
    [[ "${service_type}" == "ClusterIP" ]] || {
        echo "error: expected private ClusterIP Envoy Service, got ${service_type}" >&2
        exit 1
    }
    verify_http_route
    echo "verified: Radius deployed a programmed private Gateway at radius-system/radius"
}

verify_clean() {
    if managed_gateway_exists; then
        echo "error: managed Gateway still exists; delete the Radius application in the Copilot app first" >&2
        exit 1
    fi
    if managed_contour_exists; then
        echo "error: managed Contour still exists; delete the Radius application in the Copilot app first" >&2
        exit 1
    fi
    echo "verified: no managed Gateway or Contour release exists"
}

case "${ACTION}" in
    setup)
        require_tools
        require_target
        require_github_environment
        delete_environment_variable RADIUS_ROUTES_GATEWAY_NAME
        delete_environment_variable RADIUS_ROUTES_GATEWAY_NAMESPACE
        delete_environment_variable RADIUS_ROUTES_EXPOSURE
        verify_clean
        echo "ready: deploy .radius/app.bicep from the Copilot Radius canvas"
        ;;
    verify)
        require_tools
        verify_deployed
        ;;
    teardown)
        require_tools
        require_target
        require_github_environment
        delete_environment_variable RADIUS_ROUTES_GATEWAY_NAME
        delete_environment_variable RADIUS_ROUTES_GATEWAY_NAMESPACE
        delete_environment_variable RADIUS_ROUTES_EXPOSURE
        verify_clean
        ;;
    *)
        echo "usage: ./setup.sh {setup|verify|teardown}"
        ;;
esac
