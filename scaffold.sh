#!/usr/bin/env bash
#
# scaffold.sh
# Creates the complete folder structure for the kubernetes-observability repository.
# Run once from inside the cloned repository root.
#
# Usage:
#   chmod +x scaffold.sh
#   ./scaffold.sh

set -euo pipefail

MODULES=(
  "01-introduction-to-observability"
  "02-prometheus-configuration"
  "03-advanced-monitoring"
  "04-grafana-basics"
  "05-grafana-variables-datasources"
  "06-scaling-grafana"
  "07-dashboards-on-kubernetes"
  "08-newrelic-observability"
)

echo "Creating module directories..."

for module in "${MODULES[@]}"; do
  mkdir -p "${module}/manifests"
  mkdir -p "${module}/images"
  mkdir -p "${module}/excalidraw"

  # .gitkeep so empty directories are tracked by git
  touch "${module}/manifests/.gitkeep"
  touch "${module}/images/.gitkeep"
  touch "${module}/excalidraw/.gitkeep"

  echo "  ${module}"
done

echo ""
echo "Creating Module 01 chapter files..."

M1="01-introduction-to-observability"

CHAPTERS=(
  "01-what-is-observability.md"
  "02-prometheus-architecture.md"
  "03-apt-installation.md"
  "04-helm-installation.md"
  "05-custom-resource-definitions.md"
  "06-auto-reload.md"
  "07-grafana-setup-and-access.md"
  "08-alertmanager.md"
  "09-upgrading-the-stack.md"
  "10-architecture-recap.md"
  "99-cleanup.md"
)

for chapter in "${CHAPTERS[@]}"; do
  touch "${M1}/${chapter}"
  echo "  ${M1}/${chapter}"
done

touch "${M1}/README.md"
touch "${M1}/RUNBOOK.md"

echo ""
echo "Creating root files..."

touch TROUBLESHOOTING.md
echo "  TROUBLESHOOTING.md"

echo ""
echo "Structure created. Verify with: find . -type d -not -path './.git*' | sort"
