# Challenge Operator — Full Design & Implementation Guide

A production‑ready reference for building a Kubernetes operator in Go that provisions **ephemeral challenge pods** (per request) with **ClusterIP Services**, exposes them via **Gateway API HTTPRoutes** behind a token‑validating router, and cleans them up automatically via **TTL** or when the **CR** is deleted.

---

## 0) Goals & Non‑Goals

**Goals**

* Define custom resources to model **challenge types** and **per‑request instances**.
* Reconcile instances into **Pod + Service + HTTPRoute** triplets.
* Route frontend traffic through a **router/gateway** that performs **token auth** and supports **WebSockets**.
* Record runtime info in CR **status** (route, readiness, expiry).
* Enforce **TTL** for automatic teardown; use K8s GC via **OwnerReferences** for deletion on CR removal.
* Provide **observability** (events, metrics, logs) and **tests**.

**Non‑Goals**

* Not covering the internal logic of the challenge containers.
* Not implementing the router itself; we provide reference configs for NGINX/Envoy/Traefik.

---

## 1) High‑Level Architecture

```
Frontend ──(create request)──▶ API Gateway ──▶ create ChallengeInstance (CR)
                                                    │
                                                    ▼
                                        Challenge Operator (controller)
                                                    │
                                   ┌────────── creates / updates ──────────┐
                                   ▼                                        ▼
                                Pod (UUID)     Service (ClusterIP)     HTTPRoute (Gateway API)
                                   │                    │                      │
                                   └──── exposed internally ───────────────────┘
                                                    │
                                       Router/Gateway with token check
                                                    │
                                                    ▼
                                              WebSocket/HTTP
```

* Each **request** creates a **ChallengeInstance** (CI) CR.
* The operator generates a **UUID** for the pod, creates the **Service** and **HTTPRoute**, and writes details into **status**.
* Router proxies `/challenge/<uuid>` to the instance’s Service **only if the user token is valid**.
* On **TTL expiry** or **CR deletion**, the operator cleans up; OwnerReferences handle cascading.

---

## 2) Custom Resource Design

### 2.1 `ChallengeType` (template)

Represents a reusable template for a particular challenge.

```yaml
apiVersion: challenges.example.com/v1alpha1
kind: ChallengeType
metadata:
  name: math
spec:
  image: ghcr.io/acme/challenges/math:latest
  port: 8080
  env:                      # optional
    - name: DIFFICULTY
      value: "medium"
  resources:                # optional pod resources
    limits:
      cpu: "500m"
      memory: "512Mi"
    requests:
      cpu: "250m"
      memory: "256Mi"
  serviceAnnotations:       # optional
    prometheus.io/scrape: "true"
  routePrefix: "/challenge"  # base path for instances
```

**Notes**

* One `ChallengeType` per distinct challenge (you can have 10+ types).
* Keeps images/specs centralized and versionable.

### 2.2 `ChallengeInstance` (ephemeral per request)

Represents a single user session / instance with TTL.

```yaml
apiVersion: challenges.example.com/v1alpha1
kind: ChallengeInstance
metadata:
  name: math-<uuid>               # client may provide, or operator generates
spec:
  typeRef:
    name: math                    # references ChallengeType
  duration: 10m                   # TTL, e.g. 10 minutes
  annotations:                    # optional pass‑through to Pod/Service/Route
    router.acme.io/requireToken: "true"
  labels:                         # optional pass‑through labels
    audience: "students"
  env:                            # optional to override/extend type env
    - name: SEED
      value: "123"
status:
  phase: Pending | Running | Expired | Deleting | Error
  reason: ""
  podName: ""
  serviceName: ""
  routePath: ""
  host: ""                        # if your Gateway uses a host
  url: ""                          # convenience (scheme + host + path)
  expiresAt: ""                   # RFC3339
  conditions: []                  # standard Condition[]
```

**Why a separate Instance CR?**  It allows multiple concurrent pods per type, clear TTL, and clean ownership for GC.

---

## 3) Project Scaffolding

Use **Kubebuilder** (recommended).

```bash
kubebuilder init --domain example.com --repo github.com/acme/challenge-operator
kubebuilder create api --group challenges --version v1alpha1 --kind ChallengeType --resource --controller
kubebuilder create api --group challenges --version v1alpha1 --kind ChallengeInstance --resource --controller
```

Add Gateway API types to your Go module:

```bash
go get sigs.k8s.io/gateway-api@latest
```

Register schemes in `main.go`:

```go
import (
  gatewayv1 "sigs.k8s.io/gateway-api/apis/v1beta1" // or v1 if your cluster supports it
)

func init() {
  _ = gatewayv1.AddToScheme(scheme)
}
```

---

## 4) Reconcile Logic (Controller)

### 4.1 Watch & Ownership

* Controller watches `ChallengeInstance` objects.
* All created child objects (Pod, Service, HTTPRoute) must set **OwnerReference = Instance** so K8s GC cleans them when the Instance is deleted.

```go
ctrl.SetControllerReference(&instance, pod, r.Scheme)
ctrl.SetControllerReference(&instance, svc, r.Scheme)
ctrl.SetControllerReference(&instance, route, r.Scheme)
```

### 4.2 Core Flow (pseudocode)

```go
func (r *ChallengeInstanceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
  // 1) Load Instance; return if not found
  var inst v1alpha1.ChallengeInstance
  if err := r.Get(ctx, req.NamespacedName, &inst); err != nil {
    return ctrl.Result{}, client.IgnoreNotFound(err)
  }

  // 2) If Expired or Deleting: ensure cleanup (usually GC via OwnerRefs) and return
  if expired(inst) {
    markExpiredStatus(&inst)
    // Optionally delete inst itself or let external actor do it
    return ctrl.Result{}, r.Status().Update(ctx, &inst)
  }

  // 3) Resolve template (ChallengeType)
  var ct v1alpha1.ChallengeType
  if err := r.Get(ctx, types.NamespacedName{Name: inst.Spec.TypeRef.Name, Namespace: req.Namespace}, &ct); err != nil {
    return requeueErr(err)
  }

  // 4) Ensure Pod exists (name contains UUID); else create
  podName := desiredPodName(inst)
  pod := buildPod(podName, ct, inst) // includes env/ports/resources, labels
  ensureOwned(ctx, r.Client, &inst, pod)

  // 5) Ensure Service exists and targets the Pod labels
  svc := buildService(podName+"-svc", ct, inst, pod)
  ensureOwned(ctx, r.Client, &inst, svc)

  // 6) Ensure HTTPRoute exists mapping /challenge/<uuid> -> svc:port
  route := buildHTTPRoute(podName+"-route", ct, inst, svc)
  ensureOwned(ctx, r.Client, &inst, route)

  // 7) Detect Pod readiness; update status, routePath, url, expiresAt
  ready := isPodReady(ctx, r.Client, pod)
  updateStatus(&inst, pod, svc, route, ready)

  // 8) Requeue for TTL check (e.g., every 30s) until expiry
  return ctrl.Result{RequeueAfter: ttlOrDefault(inst, 30*time.Second)}, r.Status().Update(ctx, &inst)
}
```

**Helper behavior**

* `ensureOwned` should **CreateOrUpdate** using a hashed spec annotation to detect drift.
* `isPodReady` checks conditions and container status.
* `ttlOrDefault` returns the shorter of (now→expiry) or a small poll interval.

### 4.3 Pod Spec Highlights

* **Generate UUID** per instance (use `github.com/google/uuid`).
* Label with `challenge-type`, `instance` and a unique selector label (e.g., `app.kubernetes.io/instance`).
* Mount optional **ConfigMap/Secret** if present in type.
* Support **WebSocket** (no special pod config needed beyond port exposure).

### 4.4 Service Spec Highlights

* Type: **ClusterIP**.
* `selector` must select only this instance’s pod (use a unique label, not just `challenge-type`).
* Optionally add `sessionAffinity: ClientIP` if needed.

### 4.5 HTTPRoute Spec Highlights (Gateway API)

* `parentRefs`: your Gateway (e.g., `name: app-gateway`).
* `rules.matches.path`: `/challenge/<uuid>` (Prefix or Exact).
* `backendRefs`: the instance **Service** and **port**.
* Add annotations/filters for your router’s **token validation** (varies by implementation).

Example (v1beta1):

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: math-1234-route
  annotations:
    router.acme.io/auth: "jwt"              # example, router-specific
spec:
  parentRefs:
    - name: app-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /challenge/math-1234
      backendRefs:
        - name: math-1234-svc
          port: 8080
```

> If your cluster supports `gateway.networking.k8s.io/v1`, just update imports and `apiVersion` accordingly.

---

## 5) Status, Conditions & Events

Update `ChallengeInstance.status` to drive the frontend:

* `phase`: `Pending` → `Running` → `Expired`/`Deleting`/`Error`.
* `routePath`/`host`/`url`: what the frontend should connect to.
* `expiresAt`: RFC3339 timestamp.
* `conditions`: standard `Ready`, `Routed`, `Expired` conditions.
* Emit **Events** (`Normal`/`Warning`): `CreatedPod`, `PodReady`, `CreatedRoute`, `Expired`, `Deleted`.

This allows your **API gateway** or frontend to **poll/watch** the Instance and react to lifecycle changes.

---

## 6) TTL & Cleanup Strategy

* Parse `spec.duration` (e.g., `time.ParseDuration`).
* Compute `expiresAt = metadata.creationTimestamp + duration` and write to status.
* On or after expiry:

  * Set `phase = Expired` and add `Expired` condition.
  * Option A: **Delete the Instance CR** (which cascades children via OwnerRefs).
  * Option B: Leave CR but **delete children** explicitly; keep history in CR `status`.
* Use **finalizers** if you need custom teardown (e.g., out‑of‑cluster resources) before GC.

Finalizer flow:

1. Add finalizer `challenges.example.com/finalizer` on create.
2. On deletion, run custom cleanup (if any) then remove the finalizer.

---

## 7) Security & Token Validation Path

* The **router** (NGINX/Envoy/Traefik) should enforce token validation for `/challenge/<uuid>`.
* Approaches:

  * **External auth**: router calls an **auth service** (e.g., `/validate-token`) before proxying.
  * **JWT filter/middleware**: verify signature, audience, expiry.
* The operator can annotate the HTTPRoute with metadata the router reads (e.g., `requiredClaims`, `aud`, `sub`).
* **Never** expose Pod IPs directly to the internet; always go via Service + Gateway.
* Consider **namespace multi-tenancy** (per team/student) and **NetworkPolicy** to isolate pods.

---

## 8) RBAC

Grant the operator minimal permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: challenge-operator-role
rules:
- apiGroups: ["challenges.example.com"]
  resources: ["challengetypes", "challengeinstances"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["pods", "services", "events"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["gateway.networking.k8s.io"]
  resources: ["httproutes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

Bind to a **ServiceAccount** used by the operator Deployment.

---

## 9) Deployment Manifests

Operator Deployment (snippet):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: challenge-operator
  namespace: operators
spec:
  replicas: 1
  selector:
    matchLabels:
      app: challenge-operator
  template:
    metadata:
      labels:
        app: challenge-operator
    spec:
      serviceAccountName: challenge-operator-sa
      containers:
        - name: manager
          image: ghcr.io/acme/challenge-operator:latest
          args:
            - "--leader-elect"           # enable leader election for HA
          env:
            - name: WATCH_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
```

Gateway + HTTPRoute prerequisites:

* Ensure a **Gateway** (e.g., `app-gateway`) exists and is programmed by your chosen controller (NGINX, Envoy, Traefik, GKE Gateway, etc.).

---

## 10) Router Config (Reference)

### 10.1 NGINX (Ingress or HTTPRoute via annotation)

* Use `proxy_set_header Upgrade`/`Connection` to support **WebSockets**.
* Token validation with `auth_request` or NGINX `jwt` module; for Ingress‑NGINX use `nginx.ingress.kubernetes.io/auth-url`.

### 10.2 Envoy

* Use **JWT AuthN filter** + **External AuthZ** filter for fine‑grained claims checks.

### 10.3 Traefik

* Use **middlewares** for forward‑auth or JWT validation.

> The operator’s role is to create the **HTTPRoute** that binds the path `/challenge/<uuid>` to the Service. The router enforces auth before proxying.

---

## 11) Naming & Labeling Conventions

For instance with UUID `3f7a...` and type `math` in ns `challenges`:

* Pod: `math-3f7a`
* Service: `math-3f7a-svc`
* HTTPRoute: `math-3f7a-route`
* Labels:

  * `app.kubernetes.io/name: challenge`
  * `app.kubernetes.io/instance: math-3f7a`
  * `challenges.example.com/type: math`

Use a unique selector label (e.g., `app.kubernetes.io/instance`) so the Service targets only its pod.

---

## 12) Observability

* **Logs**: structured (zap/logr) with instance name/uuid; include reconcile duration.
* **Events**: `CreatedPod`, `PodReady`, `CreatedService`, `CreatedRoute`, `Expired`, `Deleted`.
* **Metrics** (controller‑runtime + Prometheus):

  * `challenge_instances_running{type=...}` gauge.
  * `challenge_instance_lifetime_seconds` histogram.
  * Reconcile errors counter.

Expose metrics on `/metrics` for scraping by Prometheus.

---

## 13) Testing Strategy

* **Unit tests**: build functions `buildPod`, `buildService`, `buildHTTPRoute`, duration parsing, status updates.
* **Envtest** (controller‑runtime):

  * Spin up control‑plane in test, apply CRDs, create a `ChallengeType`, then a `ChallengeInstance`.
  * Assert Pod/Service/HTTPRoute existence and status transitions.
* **E2E**: in a real cluster (kind/minikube), run the operator, create instances, verify routing and TTL delete.

---

## 14) Example: Minimal Go Builders

```go
func buildPod(name string, ct v1alpha1.ChallengeType, ci v1alpha1.ChallengeInstance) *corev1.Pod {
  labels := map[string]string{
    "app.kubernetes.io/name": "challenge",
    "app.kubernetes.io/instance": name,
    "challenges.example.com/type": ct.Name,
  }
  cn := corev1.Container{
    Name:  "challenge",
    Image: ct.Spec.Image,
    Ports: []corev1.ContainerPort{{ContainerPort: int32(ct.Spec.Port)}},
    Resources: ct.Spec.Resources,
    Env: append(envFrom(ct.Spec.Env), envFrom(ci.Spec.Env)...),
  }
  return &corev1.Pod{
    ObjectMeta: metav1.ObjectMeta{Name: name, Labels: labels},
    Spec: corev1.PodSpec{Containers: []corev1.Container{cn}},
  }
}

func buildService(name string, ct v1alpha1.ChallengeType, ci v1alpha1.ChallengeInstance, pod *corev1.Pod) *corev1.Service {
  return &corev1.Service{
    ObjectMeta: metav1.ObjectMeta{Name: name},
    Spec: corev1.ServiceSpec{
      Selector: map[string]string{"app.kubernetes.io/instance": pod.Name},
      Ports: []corev1.ServicePort{{Port: int32(ct.Spec.Port), TargetPort: intstr.FromInt(ct.Spec.Port)}},
      Type: corev1.ServiceTypeClusterIP,
    },
  }
}

func buildHTTPRoute(name string, ct v1alpha1.ChallengeType, ci v1alpha1.ChallengeInstance, svc *corev1.Service) *gatev1.HTTPRoute {
  path := fmt.Sprintf("%s/%s", ct.Spec.RoutePrefix, svc.Labels["app.kubernetes.io/instance"]) // e.g., /challenge/math-3f7a
  port := gatev1.PortNumber(ct.Spec.Port)
  return &gatev1.HTTPRoute{
    ObjectMeta: metav1.ObjectMeta{Name: name},
    Spec: gatev1.HTTPRouteSpec{
      ParentRefs: []gatev1.ParentReference{{Name: gatev1.ObjectName("app-gateway")}},
      Rules: []gatev1.HTTPRouteRule{{
        Matches: []gatev1.HTTPRouteMatch{{Path: &gatev1.HTTPPathMatch{Type: ptr(gatev1.PathMatchPathPrefix), Value: ptr(path)}}},
        BackendRefs: []gatev1.HTTPBackendRef{{BackendRef: gatev1.BackendRef{Name: gatev1.ObjectName(svc.Name), Port: &port}}},
      }},
    },
  }
}
```

> Replace `gatev1` with `gateway.networking.k8s.io/v1beta1` (or `/v1`) imports as applicable.

---

## 15) API Gateway / Frontend Flow

1. Frontend requests a challenge of type `math`.
2. Backend (API gateway) creates a `ChallengeInstance` and returns `{ route, token, expiresAt }`.
3. Frontend connects to `wss://<host>/challenge/<uuid>` with `Authorization: Bearer <token>`.
4. Router validates token; if OK, proxies to the instance Service.
5. On TTL expiry, Instance status moves to `Expired`; router eventually returns 404 as resources are deleted.

---

## 16) Operational Considerations

* **Leader election** for multi‑replica operator Deployments.
* **Backoff & idempotency** in Reconcile to handle transient API errors.
* **Rate limiting**: use controller‑runtime workqueue rate limiters.
* **Quotas/limits** per namespace/team; optionally validate `duration` via a **ValidatingWebhook** to cap TTL.
* **Garbage collection of orphaned routes**: periodic sweep that lists Instances and cleans any stray children (belt‑and‑suspenders).

---

## 17) CRD Schemas (Validation)

Use OpenAPI v3 schema in CRDs to validate fields (`duration` pattern, port ranges, enum phases in `status.conditions[].type`, etc.). Consider defaulting webhook for `duration` default (e.g., `5m`).

---

## 18) Makefile & CI Hints

Basic `make` targets (Kubebuilder template):

* `make generate` – codegen for deep copy, CRDs.
* `make manifests` – render CRDs and RBAC.
* `make docker-build` / `make docker-push` – image lifecycle.
* `make deploy` – install CRDs + deploy operator to cluster.
* CI: run `envtest` suite and `kubectl` e2e in KinD.

---

## 19) Minimal End‑to‑End Example

1. Apply CRDs and deploy operator & Gateway.
2. Create a `ChallengeType`:

```yaml
apiVersion: challenges.example.com/v1alpha1
kind: ChallengeType
metadata:
  name: math
spec:
  image: ghcr.io/acme/challenges/math:latest
  port: 8080
  routePrefix: /challenge
```

3. Create an instance:

```yaml
apiVersion: challenges.example.com/v1alpha1
kind: ChallengeInstance
metadata:
  name: math-3f7a
spec:
  typeRef:
    name: math
  duration: 5m
```

4. Observe resources:

* `kubectl get pods,svc,httproute -n <ns>`
* `kubectl get challengeinstances -o yaml` → check `status.url` & `expiresAt`.

5. Connect from frontend using returned route + token.

After 5 minutes, the operator marks as `Expired` and deletes children; GC removes Pod/Service/HTTPRoute.

---

## 20) Next Steps

* Decide on router (Ingress‑NGINX, Envoy Gateway, Traefik, GKE Gateway) and align the HTTPRoute annotations/filters.
* Implement a small **auth service** if using external‑auth pattern.
* Add **webhooks** (defaulting/validating) for better UX & safety.
* Ship **dashboards** (Grafana) for instance counts and lifetimes.

---

**You now have a complete blueprint to implement the Challenge Operator**: CRDs, controllers, routing, security, TTL, and operational playbook. When you’re ready, we can generate the initial Kubebuilder project files and Go stubs tailored to your repo structure.
