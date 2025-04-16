#!/usr/bin/env bash

# Copyright 2021 The Tekton Authors
# Licensed under the Apache License, Version 2.0

echo "🔧 Disabling Affinity Assistant (safe default)"
kubectl patch cm feature-flags -n tekton-pipelines -p '{"data":{"disable-affinity-assistant":"true"}}'

echo "🔁 Restarting Tekton controller and webhook"
kubectl rollout restart deployment tekton-pipelines-controller -n tekton-pipelines
kubectl rollout restart deployment tekton-pipelines-webhook -n tekton-pipelines

echo "🕐 Waiting for pods to refresh..."
sleep 60
echo "✅ Tekton pods refreshed"

kubectl get cm feature-flags -n tekton-pipelines -o yaml | grep disable-affinity-assistant

# --- Arch-specific overrides ---
export REGISTRY_IMAGE=ibmcom/registry:2.6.2.5
export MAVEN_IMAGE=maven:3.6.3-adoptopenjdk-11
export GOARCH=ppc64le
export BUILDER_IMAGE=gradle:5.6.2-jdk11
export TEST_TASKRUN_IGNORES="helm-upgrade-from-repo helm-upgrade-from-source golang-test kaniko"

# --- Optional: Patch registry deployments if present ---
echo "🔄 Updating registry image for ppc64le"
find task -name *registry*.yaml | xargs -I{} yq eval '(..|select(.kind?=="Deployment")|select(.metadata.name?=="registry")|.spec.template.spec.containers[0].image) |= env(REGISTRY_IMAGE)' -i {}

# --- Golang Task: Set GOARCH param ---
echo "🛠️  Adding GOARCH param to golang tasks"
find task/golang*/*/tests/run.yaml | xargs -I{} yq eval '(..|select(.kind?=="Pipeline")|.spec.tasks[].params) |= . + [{"name": "GOARCH", "value": env(GOARCH)}]' -i {}

# --- Gradle Task: Set GRADLE_IMAGE param ---
echo "🛠️  Adding GRADLE_IMAGE param to gradle tasks"
find task/gradle/*/tests/run.yaml | xargs -I{} yq eval '(..|select(.kind?=="Pipeline")|.spec.tasks[].params) |= . + [{"name": "GRADLE_IMAGE", "value": env(BUILDER_IMAGE)}]' -i {}

# --- Jib Gradle Task: Set BUILDER_IMAGE param ---
echo "🛠️  Adding BUILDER_IMAGE param to jib-gradle tasks"
find task/jib-gradle/*/tests/run.yaml | xargs -I{} yq eval '(..|select(.kind?=="Pipeline")|.spec.tasks[].params) |= . + [{"name": "BUILDER_IMAGE", "value": env(BUILDER_IMAGE)}]' -i {}

# --- Maven Tasks: Inject SUBPATH & MAVEN_IMAGE ---
echo "🛠️  Updating Maven tasks with SUBPATH and MAVEN_IMAGE (manual .m2 mount fix)"
find task/*maven*/**/tests/run.yaml | xargs -I{} yq eval '
  (.spec.tasks[] | select(.name | test("maven.*")) | .params) += 
  [{"name": "MAVEN_IMAGE", "value": env(MAVEN_IMAGE)},
   {"name": "SUBPATH", "value": "ppc64le"}]
' -i {}

# --- Enable Step Actions ---
echo "🔓 Enabling step actions"
kubectl patch cm feature-flags -n tekton-pipelines -p '{"data":{"enable-step-actions":"true"}}'
