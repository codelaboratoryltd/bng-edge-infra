#!/bin/sh

set -e
# This script uses helmfile to template Helm charts and outputs them to the current directory
# Adapted from predbat-saas-infra with workaround for https://github.com/helm/helm/issues/12010

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR=$(mktemp -d)
# Output to charts/ directory at repo root (relative to scripts/)
TARGET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/charts"
mkdir -p "$TARGET_DIR"

cp "$SCRIPT_DIR/helmfile.yaml" "$OUTPUT_DIR/"

cd $OUTPUT_DIR

helmfile template --kube-context none --include-crds --skip-tests --args="--no-hooks" --output-dir . \
--output-dir-template '{{ .OutputDir }}'

# Find all directories in the output directory
# mindepth 3 prevents top level directories from being targeted, i.e. the folder containing the kustomization.yaml
find "$OUTPUT_DIR" -mindepth 3 -type d | \
    # Use sed to replace output_dir with target_dir
    sed "s|^$OUTPUT_DIR|$TARGET_DIR|" | \
    # Sort and remove duplicates
    sort -u | \
    # Use xargs to remove directories and files in the target directory
    xargs -n1 rm -rf

# Find all files in the output directory with depth greater than 1
find "$OUTPUT_DIR" -mindepth 2 -type f | while read -r file; do
    # Replace output_dir with target_dir in the file path
    target_file=$(echo "$file" | sed "s|^$OUTPUT_DIR|$TARGET_DIR|")
    # Create the target directory if it doesn't exist
    target_dir=$(dirname "$target_file")
    mkdir -p "$target_dir"
    # Copy the file to the target directory
    cp "$file" "$target_file"
done

# Generate kustomization.yaml for each chart directory
for chart_dir in "$TARGET_DIR"/*/; do
    chart_name=$(basename "$chart_dir")
    kust_file="$chart_dir/kustomization.yaml"

    echo "apiVersion: kustomize.config.k8s.io/v1beta1" > "$kust_file"
    echo "kind: Kustomization" >> "$kust_file"
    echo "resources:" >> "$kust_file"

    # Add all yaml files recursively
    find "$chart_dir" -name "*.yaml" -not -name "kustomization.yaml" | sort | while read -r yaml_file; do
        rel_path="${yaml_file#$chart_dir}"
        echo "  - $rel_path" >> "$kust_file"
    done
done

echo "✓ Helmfile templates generated successfully"
echo "✓ Output: $TARGET_DIR"
