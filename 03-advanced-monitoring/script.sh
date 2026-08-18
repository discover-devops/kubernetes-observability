cat > promql-lab-setup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "===== PromQL Lab Setup ====="

# -------------------------
# Install dependencies
# -------------------------
sudo apt update -y
sudo apt install -y curl ca-certificates gnupg

if ! command -v helm >/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# -------------------------
# Install k3s
# -------------------------
if ! command -v k3s >/dev/null; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.31.2+k3s1" sh -s - --disable traefik --write-kubeconfig-mode 644
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Waiting for Kubernetes..."

until kubectl get nodes 2>/dev/null | grep Ready; do
  sleep 5
done

# -------------------------
# Install kube-prometheus-stack
# -------------------------
kubectl create ns monitoring --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
-n monitoring \
--version 65.1.1 \
--set grafana.service.type=NodePort \
--set grafana.service.nodePort=30080 \
--set prometheus.service.type=NodePort \
--set prometheus.service.nodePort=30090 \
--set alertmanager.service.type=NodePort \
--set alertmanager.service.nodePort=30093 \
--set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
--set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
--wait --timeout 15m

# -------------------------
# Lab namespace
# -------------------------
kubectl create ns promql-lab --dry-run=client -o yaml | kubectl apply -f -

# -------------------------
# Demo application code
# -------------------------
kubectl apply -f - <<'CM'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-app-code
  namespace: promql-lab
data:
  app.py: |
    import random,time,threading
    from flask import Flask,Response
    from prometheus_client import *

    reg=CollectorRegistry()

    REQS=Counter("demo_http_requests_total","",["exported_endpoint","method","status_code"],registry=reg)
    QUEUE=Gauge("demo_queue_depth","",registry=reg)
    INFLIGHT=Gauge("demo_inflight_requests","",registry=reg)
    LAT=Histogram("demo_http_request_duration_seconds","",["exported_endpoint","status_code"],registry=reg,buckets=(.005,.01,.025,.05,.1,.25,.5,1,2.5,5,10))
    PAY=Summary("demo_payload_bytes","",["exported_endpoint"],registry=reg)

    app=Flask(__name__)

    def observe(ep,status,dur,size):
      REQS.labels(ep,"GET",str(status)).inc()
      LAT.labels(ep,str(status)).observe(dur)
      PAY.labels(ep).observe(size)

    @app.route("/api/fast")
    def fast():
      INFLIGHT.inc();t=time.time()
      time.sleep(random.uniform(.001,.005))
      observe("fast",200,time.time()-t,2)
      INFLIGHT.dec()
      return "ok"

    @app.route("/api/slow")
    def slow():
      INFLIGHT.inc();t=time.time()
      if random.random()<0.9:
        time.sleep(random.uniform(.02,.08))
      else:
        time.sleep(random.uniform(.4,1.5))
      observe("slow",200,time.time()-t,7)
      INFLIGHT.dec()
      return "slow"

    @app.route("/api/work")
    def work():
      INFLIGHT.inc();t=time.time()
      time.sleep(random.uniform(.03,.12))
      s=500 if random.random()<0.05 else 200
      observe("work",s,time.time()-t,5)
      INFLIGHT.dec()
      return ("err",500) if s==500 else ("work",200)

    @app.route("/healthz")
    def health():
      return "ok"

    @app.route("/metrics")
    def metrics():
      return Response(generate_latest(reg),mimetype=CONTENT_TYPE_LATEST)

    def bg():
      q=5
      while True:
        q=max(0,q+random.uniform(-1,1.2))
        QUEUE.set(q)
        time.sleep(2)

    threading.Thread(target=bg,daemon=True).start()
    app.run(host="0.0.0.0",port=8080,threaded=True)
CM

# -------------------------
# Demo Deployment
# -------------------------
kubectl apply -f - <<'APP'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: promql-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: app
        image: python:3.12-slim
        command: ["/bin/sh","-c"]
        args:
        - |
          pip install flask prometheus_client >/dev/null
          python /code/app.py
        ports:
        - containerPort: 8080
          name: http
        readinessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 20
        volumeMounts:
        - name: code
          mountPath: /code
      volumes:
      - name: code
        configMap:
          name: demo-app-code
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
  namespace: promql-lab
  labels:
    app: demo-app
spec:
  selector:
    app: demo-app
  ports:
  - name: http
    port: 8080
    targetPort: http
APP

# -------------------------
# Load generator
# -------------------------
kubectl apply -f - <<'LOAD'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-loadgen
  namespace: promql-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-loadgen
  template:
    metadata:
      labels:
        app: demo-loadgen
    spec:
      containers:
      - name: load
        image: busybox
        command: ["/bin/sh","-c"]
        args:
        - |
          while true;do
            wget -qO- http://demo-app.promql-lab.svc.cluster.local:8080/api/fast >/dev/null 2>&1 || true
            wget -qO- http://demo-app.promql-lab.svc.cluster.local:8080/api/slow >/dev/null 2>&1 || true
            wget -qO- http://demo-app.promql-lab.svc.cluster.local:8080/api/work >/dev/null 2>&1 || true
            sleep .1
          done
LOAD

# -------------------------
# ServiceMonitor
# -------------------------
kubectl apply -f - <<'SM'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
    - promql-lab
  selector:
    matchLabels:
      app: demo-app
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
SM

# -------------------------
# Recording & Alert Rules
# -------------------------
kubectl apply -f - <<'RULE'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: demo-app-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: demo
    rules:
    - record: job:demo_http_requests:rate5m
      expr: sum by(job,exported_endpoint,status_code)(rate(demo_http_requests_total[5m]))

    - record: job:demo_http_request_duration_seconds:p95
      expr: histogram_quantile(0.95,sum by(le,exported_endpoint)(rate(demo_http_request_duration_seconds_bucket[5m])))

    - alert: DemoHighErrorRatio
      expr: sum(rate(demo_http_requests_total{status_code="500"}[5m])) / sum(rate(demo_http_requests_total[5m])) > 0.02
      for: 2m

    - alert: DemoHighP99Latency
      expr: histogram_quantile(0.99,sum by(le)(rate(demo_http_request_duration_seconds_bucket[5m])))>1
      for: 5m
RULE

# -------------------------
# Wait for pods
# -------------------------
kubectl rollout status deployment/demo-app -n promql-lab --timeout=5m
kubectl rollout status deployment/demo-loadgen -n promql-lab --timeout=2m

echo ""
echo "========================================="
echo "PromQL Lab Ready"
echo "========================================="
echo "Prometheus : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):30090"
echo "Grafana    : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):30080"
echo "Alertmgr   : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):30093"
echo ""
echo "Grafana password:"
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo
EOF
