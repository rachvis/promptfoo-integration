# Promptfoo on IBM Cloud GRIT + Continuous Delivery

This repository is a downloadable scaffold for running the Promptfoo AWS CodeCommit-style CI flow on IBM Cloud with:

- **IBM Cloud Git Repos and Issue Tracking (GRIT)** as the Git host.
- **IBM Cloud Continuous Delivery Tekton pipelines** as the CI runner.
- **IBM Cloud Secrets Manager** as the source of LLM provider and Promptfoo credentials.
- **Promptfoo evals and code scans** as the quality and security checks.

The full tutorial is in [`ibm-cloud-grit-continuous-delivery-promptfoo.md`](./ibm-cloud-grit-continuous-delivery-promptfoo.md). The files in this repository are ready to copy into, or use as the root of, a GRIT repository.

## Repository contents

| Path | Purpose |
| --- | --- |
| `.tekton/promptfoo-eval.yaml` | Tekton pipeline that runs `promptfoo eval`, writes JSON/HTML reports, and optionally uploads artifacts to IBM Cloud Object Storage. |
| `.tekton/promptfoo-code-scan.yaml` | Tekton pipeline that runs `promptfoo code-scans run` and posts a merge request note to GRIT. |
| `promptfooconfig.yaml` | Working sample Promptfoo eval configuration. Replace this with your application evals. |
| `.promptfoo-code-scan.yaml` | Promptfoo code scanning policy and guidance. |
| `prompts/customer-support.txt` | Example prompt used by the sample eval. |
| `scripts/promptfoo-quality-gate.sh` | Reusable jq-based pass-rate quality gate for Promptfoo JSON results. |
| `scripts/format-grit-code-scan-comment.sh` | Converts Promptfoo code-scan JSON output to a GitLab/GRIT merge request note payload. |
| `scripts/post-grit-merge-request-note.sh` | Posts the generated note payload to a GRIT merge request. |
| `scripts/upload-cos-artifacts.sh` | Uploads Promptfoo JSON/HTML reports to IBM Cloud Object Storage. |
| `scripts/bootstrap-secrets-manager.sh` | Creates or rotates required IBM Cloud Secrets Manager arbitrary secrets. |
| `package.json` | Local npm scripts and the Promptfoo dependency for reproducible CLI execution. |

## Quick start

### 1. Install local dependencies

```bash
npm install
```

### 2. Store required secrets

Create these Secrets Manager secrets and map them to secure Continuous Delivery pipeline properties:

| Secret | Required by | Notes |
| --- | --- | --- |
| `OPENAI_API_KEY` | `promptfoo-eval` | Replace with the provider key names your Promptfoo config requires. |
| `PROMPTFOO_API_KEY` | `promptfoo-code-scan` | Required for `promptfoo code-scans run` in CI. |
| `GRIT_API_TOKEN` | `promptfoo-code-scan` | GRIT personal access token with enough access to create merge request notes. |

You can create or rotate the sample secrets from a machine that has the IBM Cloud CLI and Secrets Manager plug-in installed:

```bash
export SECRETS_MANAGER_URL="https://<instance-id>.<region>.secrets-manager.appdomain.cloud"
export OPENAI_API_KEY_VALUE="..."
export PROMPTFOO_API_KEY_VALUE="..."
export GRIT_API_TOKEN_VALUE="..."

scripts/bootstrap-secrets-manager.sh
```

### 3. Run a local eval

```bash
export OPENAI_API_KEY="..."
npm run eval
```

### 4. Enforce a local quality gate

```bash
npm run eval
scripts/promptfoo-quality-gate.sh promptfoo-results.json 95
```

### 5. Configure IBM Cloud Continuous Delivery

1. Add this repository to a GRIT toolchain.
2. Create a Tekton Delivery Pipeline that uses `.tekton/promptfoo-eval.yaml` as the pipeline definition.
3. Add secure pipeline properties for `OPENAI_API_KEY`, `PROMPTFOO_API_KEY`, and `GRIT_API_TOKEN` from Secrets Manager.
4. Add a push trigger for evals.
5. Create another Tekton Delivery Pipeline that uses `.tekton/promptfoo-code-scan.yaml`.
6. Add a merge-request trigger and bind these parameters from the GRIT/GitLab webhook payload:

| Parameter | Typical value |
| --- | --- |
| `GRIT_PROJECT_ID` | `$(event.project.id)` |
| `GRIT_MERGE_REQUEST_IID` | `$(event.object_attributes.iid)` |
| `TARGET_BRANCH` | `$(event.object_attributes.target_branch)` |
| `SOURCE_SHA` | `$(event.object_attributes.last_commit.id)` |

Inspect a real PipelineRun event payload in the Continuous Delivery UI before relying on these expressions, because payload fields can vary by trigger configuration.

## Generated outputs

The pipelines and scripts generate these files:

- `promptfoo-results.json`
- `promptfoo-report.html`
- `promptfoo-code-scan.json`
- `merge-request-note.json`

They are ignored by Git so you can safely run the workflow locally.
