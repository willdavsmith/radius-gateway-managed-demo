#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ] || shopt -oq posix 2>/dev/null; then
    echo "error: run this script as ./setup.sh or bash setup.sh, not sh setup.sh" >&2
    exit 2
fi

set -euo pipefail

readonly REPO="${DEMO_REPO:-willdavsmith/radius-gateway-managed-demo}"
readonly ENVIRONMENT="${DEMO_ENVIRONMENT:-azure}"
readonly WORKFLOW_REF="${DEMO_WORKFLOW_REF:-cleanup-verification}"
readonly APPLICATION="gateway-managed-demo"
readonly ACTION="${1:-help}"
readonly OWNERSHIP_ANNOTATION="radius-project.io/routes-gateway-lifecycle"
readonly OWNERSHIP_VALUE="v1"
readonly -a GATEWAY_API_CRDS=(
    "gatewayclasses.gateway.networking.k8s.io"
    "gateways.gateway.networking.k8s.io"
    "httproutes.gateway.networking.k8s.io"
    "backendtlspolicies.gateway.networking.k8s.io"
    "referencegrants.gateway.networking.k8s.io"
    "grpcroutes.gateway.networking.k8s.io"
    "tcproutes.gateway.networking.k8s.io"
    "tlsroutes.gateway.networking.k8s.io"
    "udproutes.gateway.networking.k8s.io"
)
readonly -a RECIPE_OUTPUT_TYPES=(
    "deployments.apps"
    "services"
)
readonly -a ROUTE_OUTPUT_TYPES=(
    "httproutes.gateway.networking.k8s.io"
    "tcproutes.gateway.networking.k8s.io"
    "tlsroutes.gateway.networking.k8s.io"
    "udproutes.gateway.networking.k8s.io"
)

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

require_teardown_target() {
    require_target
    if ((${#ENVIRONMENT} > 63)) ||
        [[ ! "${ENVIRONMENT}" =~ ^[[:alnum:]]([-.A-Za-z0-9_]*[[:alnum:]])?$ ]]; then
        echo "error: DEMO_ENVIRONMENT must also be a valid Kubernetes label value" >&2
        exit 1
    fi
    [[ -n "${WORKFLOW_REF}" ]] || {
        echo "error: DEMO_WORKFLOW_REF must not be empty" >&2
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

require_delete_workflow() {
    if ! gh api -X GET \
        "repos/${REPO}/contents/.github/workflows/delete-application.yml" \
        -f "ref=${WORKFLOW_REF}" >/dev/null 2>&1; then
        echo "error: delete-application.yml is not available on ${REPO}@${WORKFLOW_REF}" >&2
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

managed_gateway_class_exists() {
    kubectl get gatewayclass contour >/dev/null 2>&1
}

owned_gateway_api_crds() {
    local crd
    local object
    for crd in "${GATEWAY_API_CRDS[@]}"; do
        if ! object="$(
            kubectl get customresourcedefinition "${crd}" \
                --ignore-not-found -o json
        )"; then
            echo "error: failed to inspect Gateway API CRD ${crd}" >&2
            return 1
        fi
        if [[ -n "${object}" ]] &&
            jq -e \
                --arg annotation "${OWNERSHIP_ANNOTATION}" \
                --arg ownership "${OWNERSHIP_VALUE}" \
                '.metadata.annotations[$annotation] == $ownership' \
                <<<"${object}" >/dev/null; then
            printf '%s\n' "${crd}"
        fi
    done
}

delete_orphaned_recipe_outputs() {
    local resource_type
    local route_api_resources
    local selector
    selector="radapp.io/application=${APPLICATION},radapp.io/environment=${ENVIRONMENT}"

    route_api_resources="$(
        kubectl api-resources \
            --api-group=gateway.networking.k8s.io \
            -o name
    )" || {
        echo "error: failed to discover Gateway API resource types" >&2
        exit 1
    }

    echo "removing orphaned recipe outputs with selector ${selector}"
    for resource_type in "${RECIPE_OUTPUT_TYPES[@]}"; do
        kubectl delete "${resource_type}" --all-namespaces \
            --selector "${selector}" --ignore-not-found --wait=true
    done
    for resource_type in "${ROUTE_OUTPUT_TYPES[@]}"; do
        if grep -Fxq "${resource_type}" <<<"${route_api_resources}"; then
            kubectl delete "${resource_type}" --all-namespaces \
                --selector "${selector}" --ignore-not-found --wait=true
        fi
    done
}

dispatch_delete_workflow() {
    local run_id
    local run_url

    run_url="$(
        gh workflow run delete-application.yml \
            --repo "${REPO}" \
            --ref "${WORKFLOW_REF}" \
            -f "environment=${ENVIRONMENT}" \
            -f "application=${APPLICATION}"
    )" || {
        echo "error: failed to dispatch delete-application.yml on ${REPO}@${WORKFLOW_REF}" >&2
        exit 1
    }
    run_id="${run_url##*/}"
    [[ "${run_id}" =~ ^[0-9]+$ ]] || {
        echo "error: workflow dispatch did not return a run URL" >&2
        exit 1
    }

    gh run watch "${run_id}" --repo "${REPO}" --exit-status
}

verify_http_route() {
    local attempt
    local gateway
    local routes
    for ((attempt = 1; attempt <= 24; attempt++)); do
        routes="$(
            kubectl get httproute -A \
                -l radapp.io/application=gateway-managed-demo -o json
        )"
        gateway="$(kubectl get gateway radius -n radius-system -o json)"
        if jq -e '
          .items | length == 1 and
          all(.[];
            any(.spec.parentRefs[]?;
              .name == "radius" and .namespace == "radius-system"))
        ' <<<"${routes}" >/dev/null &&
            jq -e '
              any(.status.listeners[]?;
                .name == "http" and .attachedRoutes >= 1)
            ' <<<"${gateway}" >/dev/null; then
            echo "verified: app HTTPRoute is attached to radius-system/radius"
            return 0
        fi
        sleep 5
    done
    echo "error: app HTTPRoute was not attached to radius-system/radius" >&2
    return 1
}

verify_deployed() {
    local controller
    local service_type
    helm status contour -n radius-system >/dev/null 2>&1 || {
        echo "error: managed Contour release was not deployed" >&2
        exit 1
    }
    controller="$(
        kubectl get gatewayclass contour -o jsonpath='{.spec.controllerName}'
    )"
    [[ "${controller}" == "projectcontour.io/gateway-controller" ]] || {
        echo "error: GatewayClass contour uses unexpected controller ${controller}" >&2
        exit 1
    }
    kubectl get gateway radius -n radius-system >/dev/null
    kubectl wait --for=condition=Programmed gateway/radius \
        -n radius-system --timeout=2m
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

verify_lifecycle_resources_clean() {
    local owned_crds
    if managed_gateway_class_exists; then
        echo "error: managed GatewayClass contour still exists" >&2
        exit 1
    fi
    owned_crds="$(owned_gateway_api_crds)"
    if [[ -n "${owned_crds}" ]]; then
        echo "error: Radius-owned Gateway API CRDs still exist:" >&2
        printf '%s\n' "${owned_crds}" >&2
        exit 1
    fi
    echo "verified: no managed GatewayClass or owned Gateway API CRDs exist"
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
        echo "ready: trigger run-rad-commands.yml for GitHub Environment ${ENVIRONMENT}"
        ;;
    verify)
        require_tools
        verify_deployed
        ;;
    teardown)
        require_tools
        require_teardown_target
        require_github_environment
        require_delete_workflow
        delete_environment_variable RADIUS_ROUTES_GATEWAY_NAME
        delete_environment_variable RADIUS_ROUTES_GATEWAY_NAMESPACE
        delete_environment_variable RADIUS_ROUTES_EXPOSURE
        delete_orphaned_recipe_outputs
        dispatch_delete_workflow
        verify_clean
        verify_lifecycle_resources_clean
        ;;
    *)
        echo "usage: ./setup.sh {setup|verify|teardown}"
        ;;
esac
