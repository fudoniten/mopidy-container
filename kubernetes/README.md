# Kubernetes Deployment

This directory contains Kubernetes manifests for deploying Mopidy to a Kubernetes cluster.

## Files

- **deployment.yaml** - Deployment with health probes and resource limits
- **service.yaml** - Services for HTTP and MPD interfaces
- **secrets.yaml** - Example Secret for credentials (DO NOT commit real secrets)
- **storage.yaml** - PersistentVolumeClaim for music library and ConfigMap for podcasts
- **kustomization.yaml** - Kustomize configuration for easy deployment

## Quick Start

### 1. Create Namespace

```bash
kubectl create namespace mopidy
```

### 2. Create Secrets

**Important**: Do not use the example secrets.yaml file directly. Create secrets securely:

```bash
kubectl create secret generic mopidy-secrets \
  --from-literal=spotify-client-id=YOUR_CLIENT_ID \
  --from-literal=spotify-client-secret=YOUR_CLIENT_SECRET \
  --from-literal=icecast-password=YOUR_ICECAST_PASSWORD \
  -n mopidy
```

### 3. Configure Storage

Edit `storage.yaml` to match your cluster's storage configuration:

- Set appropriate `storageClassName` for your cluster
- Adjust storage size based on your music library
- Configure access mode (ReadOnlyMany for NFS, ReadWriteOnce for local storage)

### 4. Deploy with Kubectl

```bash
# Apply all manifests
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f storage.yaml

# Check deployment status
kubectl get pods -n mopidy
kubectl logs -f -n mopidy deployment/mopidy
```

### 5. Deploy with Kustomize

```bash
# Deploy using kustomize
kubectl apply -k .

# Or with kubectl kustomize
kubectl kustomize . | kubectl apply -f -
```

## Health Checks

The deployment includes three types of probes:

### Startup Probe
- **Purpose**: Allows Mopidy time to initialize (up to 60 seconds)
- **Configuration**: 12 failures × 5s = 60 seconds
- **Use**: Prevents premature restart during slow startup

### Liveness Probe
- **Purpose**: Detects if Mopidy has crashed and needs restart
- **Configuration**: Checks every 30s, 3 failures = restart
- **Endpoint**: `GET /mopidy/api` on port 6680

### Readiness Probe
- **Purpose**: Determines if pod is ready to receive traffic
- **Configuration**: Checks every 10s, 3 failures = remove from service
- **Effect**: Pod removed from service endpoints when failing

## Accessing Mopidy

### Within the Cluster

HTTP interface:
```bash
curl http://mopidy-http.mopidy.svc.cluster.local:6680/mopidy/api
```

MPD interface:
```bash
# From another pod
nc mopidy-mpd.mopidy.svc.cluster.local 6600
```

### Port Forwarding (for testing)

```bash
# Forward HTTP interface
kubectl port-forward -n mopidy svc/mopidy-http 6680:6680

# Access at http://localhost:6680/muse
```

### Ingress (for external access)

Uncomment and configure the Ingress section in `service.yaml`:

1. Set your ingress class (nginx, traefik, etc.)
2. Configure hostname
3. Add TLS certificate if needed

Example:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mopidy
  namespace: mopidy
spec:
  ingressClassName: nginx
  rules:
  - host: mopidy.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: mopidy-http
            port:
              number: 6680
```

## Resource Requirements

Default resource limits (adjust based on your needs):

```yaml
requests:
  memory: "256Mi"
  cpu: "100m"
limits:
  memory: "512Mi"
  cpu: "500m"
```

Typical resource usage:
- **Idle**: ~150Mi memory, ~10m CPU
- **Playing**: ~200Mi memory, ~50-100m CPU
- **Transcoding**: Up to 500m CPU

## Monitoring

### Check Pod Health

```bash
# View pod status (includes health check status)
kubectl get pods -n mopidy

# Describe pod to see probe details
kubectl describe pod -n mopidy -l app=mopidy

# View events for probe failures
kubectl get events -n mopidy --sort-by='.lastTimestamp'
```

### View Logs

```bash
# Follow logs
kubectl logs -f -n mopidy deployment/mopidy

# View previous container logs (if restarted)
kubectl logs -n mopidy deployment/mopidy --previous
```

### Check Service Endpoints

```bash
# View service endpoints (should show pod IP if ready)
kubectl get endpoints -n mopidy

# Test service connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n mopidy -- \
  curl http://mopidy-http:6680/mopidy/api
```

## Scaling

The Deployment is configured for a single replica by default. If you need multiple replicas:

1. Ensure music storage uses `ReadOnlyMany` access mode (e.g., NFS)
2. Consider using a StatefulSet if you need per-instance state
3. Update replica count:

```bash
kubectl scale deployment mopidy -n mopidy --replicas=3
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -n mopidy -l app=mopidy

# Common issues:
# - ImagePullBackOff: Check image name and registry access
# - CrashLoopBackOff: Check logs for errors
# - Pending: Check storage/resource availability
```

### Health Check Failures

```bash
# Check probe status
kubectl describe pod -n mopidy -l app=mopidy | grep -A 10 "Liveness\|Readiness\|Startup"

# Test health endpoint manually
kubectl exec -it -n mopidy deployment/mopidy -- \
  curl -f http://localhost:6680/mopidy/api
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n mopidy

# Check volume mounts
kubectl describe pod -n mopidy -l app=mopidy | grep -A 5 "Mounts:"

# Verify permissions (should be UID 1000)
kubectl exec -it -n mopidy deployment/mopidy -- ls -la /var/lib/mopidy/music
```

### Missing Secrets

```bash
# List secrets
kubectl get secrets -n mopidy

# Verify secret keys
kubectl describe secret mopidy-secrets -n mopidy

# Create missing secret
kubectl create secret generic mopidy-secrets \
  --from-literal=spotify-client-id=... \
  -n mopidy
```

## Updating

### Update Image

```bash
# Update to new image version
kubectl set image deployment/mopidy mopidy=registry.kube.sea.fudo.link/mopidy-server:v1.2.3 -n mopidy

# Watch rollout
kubectl rollout status deployment/mopidy -n mopidy
```

### Update Configuration

```bash
# Edit deployment
kubectl edit deployment mopidy -n mopidy

# Or update secrets
kubectl delete secret mopidy-secrets -n mopidy
kubectl create secret generic mopidy-secrets --from-literal=... -n mopidy

# Restart pods to pick up new secrets
kubectl rollout restart deployment/mopidy -n mopidy
```

## Cleanup

```bash
# Delete all resources
kubectl delete namespace mopidy

# Or delete individually
kubectl delete -f deployment.yaml
kubectl delete -f service.yaml
kubectl delete -f storage.yaml
kubectl delete secret mopidy-secrets -n mopidy
```
