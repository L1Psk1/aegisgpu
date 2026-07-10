# AegisGPU

AegisGPU is a cloud-native infrastructure lab demonstrating the lifecycle of a Python API from local development to containerization and Kubernetes orchestration.

## Project Overview

The project includes:

* FastAPI microservice
* Docker containerization
* Local Kubernetes cluster using kind
* Kubernetes Deployment
* ClusterIP Service
* 3 application replicas
* Self-healing validation
* ConfigMap-based configuration
* Secret injection
* Rolling updates
* Readiness and liveness probes
* CPU and memory requests and limits

## Architecture

```text
Client
  |
  v
Kubernetes Service
  |
  v
Deployment
  |
  +-- Pod 1
  +-- Pod 2
  +-- Pod 3
        |
        v
FastAPI Container
```

## Technology Stack

* Ubuntu Linux
* Python
* FastAPI
* Uvicorn
* Docker
* Kubernetes
* kind
* kubectl
* YAML
* Git

## Project Structure

```text
aegisgpu/
├── app/
│   ├── main.py
│   └── requirements.txt
├── k8s/
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── secret.example.yaml
│   └── service.yaml
├── Dockerfile
├── .gitignore
└── README.md
```

## Build the Docker Image

```bash
docker build -t aegisgpu-api:v1 .
```

## Create the Kubernetes Cluster

```bash
kind create cluster --name aegisgpu
```

## Load the Image into kind

```bash
kind load docker-image aegisgpu-api:v1 --name aegisgpu
```

## Create the Local Secret

```bash
cp k8s/secret.example.yaml k8s/secret.yaml
```

Edit `k8s/secret.yaml` and replace:

```text
replace-me
```

with your local API key.

## Deploy to Kubernetes

```bash
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

## Verify the Deployment

```bash
kubectl get nodes
kubectl get deployments
kubectl get pods
kubectl get svc
```

## Access the API

```bash
kubectl port-forward svc/aegisgpu-service 8000:8000
```

Open:

```text
http://localhost:8000
http://localhost:8000/docs
```

## Kubernetes Features Demonstrated

* Desired state management
* Pod self-healing
* Horizontal replica scaling
* Service-based pod discovery
* Externalized configuration
* Secret injection
* Rolling updates
* Health probes
* Resource management

## Status

AegisGPU v1.0 — Completed
