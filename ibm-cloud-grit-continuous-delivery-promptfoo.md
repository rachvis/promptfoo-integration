# IBM Cloud GRIT, Continuous Delivery, and Secrets Manager integration for Promptfoo

This tutorial mirrors the Promptfoo AWS CodeCommit + CodeBuild flow, but uses IBM Cloud Git Repos and Issue Tracking (GRIT), IBM Cloud Continuous Delivery Tekton pipelines, and IBM Cloud Secrets Manager.

Use this setup when you want to:

- Run `promptfoo eval` on every push or merge request in an IBM-hosted GRIT repository.
- Fail a Continuous Delivery pipeline run when promptfoo assertions fail.
- Persist JSON and HTML eval reports as pipeline artifacts or downloadable run outputs.
- Run `promptfoo code-scans run` against GRIT merge requests and post a summary note back to the merge request by using the GitLab-compatible API.
- Keep provider credentials and Promptfoo API keys in IBM Cloud Secrets Manager instead of storing them in repository files or plaintext pipeline variables.

> Terminology note: IBM Cloud GRIT is IBM-hosted Git Repos and Issue Tracking, built on GitLab Community Edition. GitLab calls pull requests **merge requests**, so this tutorial uses "merge request" for the IBM Cloud flow.


## Downloadable scaffold included

This repository now contains the runnable pipeline and helper code described in the tutorial:

- `.tekton/promptfoo-eval.yaml` for Promptfoo eval PipelineRuns.
- `.tekton/promptfoo-code-scan.yaml` for GRIT merge request code scans.
- `scripts/*.sh` helper scripts for quality gates, merge request comments, COS uploads, and Secrets Manager bootstrapping.
- `promptfooconfig.yaml`, `.promptfoo-code-scan.yaml`, and `prompts/customer-support.txt` as a working sample Promptfoo project.
- `README.md` with quick-start commands and file-by-file usage.

You can download or clone this repository, push it to a GRIT repository, and then point IBM Cloud Continuous Delivery at the `.tekton` pipeline definitions.

## Prerequisites

- An IBM Cloud account with access to a resource group where you can create services.
- An IBM Cloud Continuous Delivery service instance and toolchain.
- A GRIT repository that contains a Promptfoo config such as `promptfooconfig.yaml`.
- A Tekton Delivery Pipeline in the same toolchain as the GRIT repository.
- LLM provider credentials stored in IBM Cloud Secrets Manager, for example an `OPENAI_API_KEY` secret.
- A `PROMPTFOO_API_KEY` secret in IBM Cloud Secrets Manager if you want to run `promptfoo code-scans run`.
- A GRIT personal access token (PAT) with `api` scope if you want the pipeline to post merge request notes. Store this PAT in Secrets Manager as `GRIT_API_TOKEN`.
- Basic shell tools available in the pipeline task image: `git`, `node`, `npm`, `jq`, and `curl`.

## Architecture

1. Developers push commits or open/update merge requests in GRIT.
2. A Continuous Delivery Git trigger starts a Tekton PipelineRun.
3. The pipeline resolves nonsecret properties from Tekton parameters and secret values from Secrets Manager-backed secure properties.
4. Promptfoo runs evals, writes JSON/HTML reports, and exits nonzero when assertions or custom quality gates fail.
5. For merge requests, Promptfoo code scanning writes JSON output, the pipeline formats a Markdown summary, and the GitLab-compatible GRIT API posts that summary as a merge request note.

## 1. Create or connect the GRIT repository

1. In the IBM Cloud console, open **Platform Automation > Toolchains**.
2. Create a toolchain or open an existing toolchain.
3. Add a **Git Repos and Issue Tracking** tool integration.
4. Create a new repository, clone an existing sample, or connect your existing repository.
5. Commit your Promptfoo configuration to the repository root:

```text
promptfooconfig.yaml
package.json                 # optional, if your eval target needs local dependencies
.tekton/promptfoo-eval.yaml
.tekton/promptfoo-code-scan.yaml
```

GRIT supports merge requests and is hosted by IBM on GitLab Community Edition. IBM Cloud user passwords are not used for Git operations, so create a GRIT PAT or SSH key for local Git and API automation.

## 2. Store secrets in IBM Cloud Secrets Manager

Create the secrets that your evals and code scans need. The exact provider keys depend on your Promptfoo providers.

Recommended secret names:

| Secret name | Purpose |
| --- | --- |
| `OPENAI_API_KEY` | Example LLM provider key for Promptfoo evals. |
| `PROMPTFOO_API_KEY` | Required for `promptfoo code-scans run` outside hosted GitHub Action flows. |
| `GRIT_API_TOKEN` | GRIT PAT with `api` scope, used to post merge request notes. |

You can wire Secrets Manager into Continuous Delivery in either of these ways:

- **Simple pipeline secure properties:** Add secure environment properties in the Tekton pipeline UI and select the secret from the toolchain vault integration when available.
- **Externalized properties:** Store Tekton property definitions in Git and use Kustomize + External Secrets to sync values from IBM Cloud Secrets Manager into pipeline properties. This is the better option when you want all nonsecret property definitions versioned with the repository.

For this tutorial, define these Tekton parameters and map their values from secure properties or externalized properties:

```yaml
params:
  - name: OPENAI_API_KEY
    type: string
  - name: PROMPTFOO_API_KEY
    type: string
  - name: GRIT_API_TOKEN
    type: string
  - name: GRIT_API_BASE_URL
    type: string
    default: https://us-south.git.cloud.ibm.com/api/v4
```

Adjust `GRIT_API_BASE_URL` for your GRIT region, for example `https://eu-gb.git.cloud.ibm.com/api/v4`.

## 3. Create a Continuous Delivery Tekton pipeline

1. In the same toolchain, add or open a **Delivery Pipeline** tool integration.
2. Choose **Tekton** as the pipeline type.
3. Add the GRIT repository as the pipeline definition repository.
4. Set the pipeline definition path to `.tekton/promptfoo-eval.yaml` for evals.
5. Choose an IBM-managed worker or a private worker.
6. Add secure environment properties for `OPENAI_API_KEY`, `PROMPTFOO_API_KEY`, and `GRIT_API_TOKEN`, or configure externalized properties backed by Secrets Manager.
7. Save the pipeline.

Continuous Delivery Git triggers can run on commit pushes and pull/merge-request events. IBM Cloud also exposes the triggering webhook payload to Tekton resources with `$(event...)` expressions, which you will use later for merge request context.

## 4. Run `promptfoo eval` in Continuous Delivery

Create `.tekton/promptfoo-eval.yaml` in your GRIT repository.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: promptfoo-eval
spec:
  params:
    - name: OPENAI_API_KEY
      type: string
    - name: PROMPTFOO_CACHE_PATH
      type: string
      default: .promptfoo/cache
  workspaces:
    - name: source
  tasks:
    - name: eval
      taskSpec:
        params:
          - name: OPENAI_API_KEY
            type: string
          - name: PROMPTFOO_CACHE_PATH
            type: string
        workspaces:
          - name: source
        steps:
          - name: run-promptfoo-eval
            image: node:20-bookworm
            workingDir: $(workspaces.source.path)
            env:
              - name: OPENAI_API_KEY
                value: $(params.OPENAI_API_KEY)
              - name: PROMPTFOO_CACHE_PATH
                value: $(params.PROMPTFOO_CACHE_PATH)
            script: |
              #!/usr/bin/env bash
              set -euo pipefail

              npm install -g promptfoo

              promptfoo eval \
                -c promptfooconfig.yaml \
                --share \
                --fail-on-error \
                -o promptfoo-results.json \
                -o promptfoo-report.html
      params:
        - name: OPENAI_API_KEY
          value: $(params.OPENAI_API_KEY)
        - name: PROMPTFOO_CACHE_PATH
          value: $(params.PROMPTFOO_CACHE_PATH)
      workspaces:
        - name: source
          workspace: source
```

### What this does

- Loads `OPENAI_API_KEY` from a secure Tekton property that is backed by Secrets Manager.
- Runs the eval suite defined in `promptfooconfig.yaml`.
- Fails the PipelineRun when Promptfoo assertions fail because `--fail-on-error` is set.
- Writes `promptfoo-results.json` and `promptfoo-report.html` into the checked-out workspace.
- Uses `PROMPTFOO_CACHE_PATH` so promptfoo can reuse cached responses when your worker/workspace strategy supports it.

### Artifact handling

Tekton does not use AWS CodeBuild-style `artifacts` blocks. Use one of these approaches:

- Download the PipelineRun logs and workspace outputs from the Continuous Delivery UI if that is enough for your audit trail.
- Add a follow-up Tekton step that uploads `promptfoo-results.json` and `promptfoo-report.html` to IBM Cloud Object Storage.
- Publish the HTML report to an internal static site or evidence bucket if your organization already uses DevSecOps evidence storage.

Example upload step for IBM Cloud Object Storage, assuming you provide `COS_BUCKET` and install/configure the IBM Cloud CLI in your image:

```bash
ibmcloud cos object-put \
  --bucket "$COS_BUCKET" \
  --key "promptfoo/${PIPELINE_RUN_NAME:-manual}/promptfoo-results.json" \
  --body promptfoo-results.json

ibmcloud cos object-put \
  --bucket "$COS_BUCKET" \
  --key "promptfoo/${PIPELINE_RUN_NAME:-manual}/promptfoo-report.html" \
  --body promptfoo-report.html
```

## 5. Add a custom quality gate

If you want a custom pass-rate threshold instead of `--fail-on-error`, write JSON output first and evaluate the stats in a second command.

Replace the eval command with this script:

```bash
#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get install -y jq
npm install

npx promptfoo eval \
  -c promptfooconfig.yaml \
  --share \
  -o promptfoo-results.json \
  -o promptfoo-report.html

scripts/promptfoo-quality-gate.sh promptfoo-results.json 95
```

This lets you fail the pipeline only when the eval suite drops below a threshold that your team defines.

## 6. Trigger evals on pushes and merge requests

Create two Continuous Delivery Git triggers:

### Push trigger

1. Open your Tekton pipeline in the toolchain.
2. Add a **Git** trigger.
3. Select the GRIT repository.
4. Set the event type to commit push.
5. Set the branch pattern, for example `main` or `release/*`.
6. Save the trigger.

### Merge request trigger

1. Add another **Git** trigger.
2. Select the GRIT repository.
3. Enable pull/merge-request opened and updated events.
4. Include or exclude draft merge requests according to your review policy.
5. Include or exclude fork merge requests according to your security policy. For most teams, do not expose high-value secrets to untrusted forks.
6. Save the trigger.

If you need more precise trigger logic, use a CEL filter and inspect a previous PipelineRun's raw event payload from the Pipeline Run details page. Event payload fields are repository-provider specific.

## 7. Run Promptfoo code scans on GRIT merge requests

Promptfoo hosted GitHub Actions can post inline review comments on GitHub pull requests, but GRIT merge requests are not a first-class review target for `promptfoo code-scans run`. For GRIT, use this pattern:

1. Run the scanner in a Tekton task.
2. Save JSON output to `promptfoo-code-scan.json`.
3. Format a Markdown summary with `jq`.
4. Post a single merge request note through the GitLab-compatible GRIT API.

Create `.tekton/promptfoo-code-scan.yaml`:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: promptfoo-code-scan
spec:
  params:
    - name: PROMPTFOO_API_KEY
      type: string
    - name: GRIT_API_TOKEN
      type: string
    - name: GRIT_API_BASE_URL
      type: string
      default: https://us-south.git.cloud.ibm.com/api/v4
    - name: GRIT_PROJECT_ID
      type: string
    - name: GRIT_MERGE_REQUEST_IID
      type: string
    - name: TARGET_BRANCH
      type: string
      default: main
    - name: SOURCE_SHA
      type: string
      default: HEAD
  workspaces:
    - name: source
  tasks:
    - name: code-scan
      taskSpec:
        params:
          - name: PROMPTFOO_API_KEY
            type: string
          - name: GRIT_API_TOKEN
            type: string
          - name: GRIT_API_BASE_URL
            type: string
          - name: GRIT_PROJECT_ID
            type: string
          - name: GRIT_MERGE_REQUEST_IID
            type: string
          - name: TARGET_BRANCH
            type: string
          - name: SOURCE_SHA
            type: string
        workspaces:
          - name: source
        steps:
          - name: run-code-scan
            image: node:20-bookworm
            workingDir: $(workspaces.source.path)
            env:
              - name: PROMPTFOO_API_KEY
                value: $(params.PROMPTFOO_API_KEY)
              - name: GRIT_API_TOKEN
                value: $(params.GRIT_API_TOKEN)
              - name: GRIT_API_BASE_URL
                value: $(params.GRIT_API_BASE_URL)
              - name: GRIT_PROJECT_ID
                value: $(params.GRIT_PROJECT_ID)
              - name: GRIT_MERGE_REQUEST_IID
                value: $(params.GRIT_MERGE_REQUEST_IID)
              - name: TARGET_BRANCH
                value: $(params.TARGET_BRANCH)
              - name: SOURCE_SHA
                value: $(params.SOURCE_SHA)
            script: |
              #!/usr/bin/env bash
              set -euo pipefail

              apt-get update
              apt-get install -y jq curl git
              npm install -g promptfoo

              if [ -z "$GRIT_PROJECT_ID" ] || [ -z "$GRIT_MERGE_REQUEST_IID" ]; then
                echo "GRIT_PROJECT_ID and GRIT_MERGE_REQUEST_IID are required for merge request scans"
                exit 1
              fi

              git fetch origin "$TARGET_BRANCH:$TARGET_BRANCH"

              promptfoo code-scans run . \
                --base "$TARGET_BRANCH" \
                --compare "$SOURCE_SHA" \
                --json \
                > promptfoo-code-scan.json

              COMMENT_BODY=$(jq -r '
                def sev(c): if c.severity then "\(.severity | ascii_upcase): " else "" end;
                [
                  "## Promptfoo Code Scan",
                  "",
                  (.review // "Scan complete."),
                  "",
                  "### Findings",
                  (
                    if (.comments | length) == 0 then
                      "- No findings"
                    else
                      (.comments[:20] | map(
                        "- " + sev(.) +
                        (if .file then "`\(.file)\(if .line then ":\(.line)" else "" end)` - " else "" end) +
                        .finding
                      ) | .[])
                    end
                  ),
                  "",
                  "[View code scanning docs](https://www.promptfoo.dev/docs/code-scanning/cli/)"
                ] | join("\n")
              ' promptfoo-code-scan.json)

              jq -n --arg body "$COMMENT_BODY" '{body: $body}' > merge-request-note.json

              curl --fail-with-body \
                --request POST \
                --header "PRIVATE-TOKEN: ${GRIT_API_TOKEN}" \
                --header "Content-Type: application/json" \
                --data @merge-request-note.json \
                "${GRIT_API_BASE_URL}/projects/${GRIT_PROJECT_ID}/merge_requests/${GRIT_MERGE_REQUEST_IID}/notes"
      params:
        - name: PROMPTFOO_API_KEY
          value: $(params.PROMPTFOO_API_KEY)
        - name: GRIT_API_TOKEN
          value: $(params.GRIT_API_TOKEN)
        - name: GRIT_API_BASE_URL
          value: $(params.GRIT_API_BASE_URL)
        - name: GRIT_PROJECT_ID
          value: $(params.GRIT_PROJECT_ID)
        - name: GRIT_MERGE_REQUEST_IID
          value: $(params.GRIT_MERGE_REQUEST_IID)
        - name: TARGET_BRANCH
          value: $(params.TARGET_BRANCH)
        - name: SOURCE_SHA
          value: $(params.SOURCE_SHA)
      workspaces:
        - name: source
          workspace: source
```

This posts one general merge request note with a summary and up to 20 findings. It intentionally avoids inline review-comment semantics because Promptfoo scanner output is currently tuned for GitHub review workflows.

## 8. Pass merge request context into the code-scan pipeline

For the merge request trigger, bind pipeline parameters from the Git trigger payload.

The exact payload shape can vary, so first run the trigger once and inspect **Pipeline Run details > Show context** in Continuous Delivery. For GRIT/GitLab-style merge request hooks, the values you typically need are:

| Pipeline parameter | Typical event value |
| --- | --- |
| `GRIT_PROJECT_ID` | `$(event.project.id)` |
| `GRIT_MERGE_REQUEST_IID` | `$(event.object_attributes.iid)` |
| `TARGET_BRANCH` | `$(event.object_attributes.target_branch)` |
| `SOURCE_SHA` | `$(event.object_attributes.last_commit.id)` |

If your trigger UI supports direct parameter mappings, add those values as trigger properties. If you define trigger bindings in YAML, use the same event expressions in your `TriggerBinding`.

Example binding pattern:

```yaml
apiVersion: tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: promptfoo-code-scan-binding
spec:
  params:
    - name: GRIT_PROJECT_ID
      value: $(event.project.id)
    - name: GRIT_MERGE_REQUEST_IID
      value: $(event.object_attributes.iid)
    - name: TARGET_BRANCH
      value: $(event.object_attributes.target_branch)
    - name: SOURCE_SHA
      value: $(event.object_attributes.last_commit.id)
```

## 9. Recommended access controls

### Continuous Delivery access

Grant pipeline maintainers enough access to edit toolchains, Delivery Pipeline definitions, and trigger properties. Grant developers enough access to view PipelineRuns and logs.

### Secrets Manager access

Grant the pipeline's service identity only read access to the secrets it needs:

- `OPENAI_API_KEY` for evals.
- `PROMPTFOO_API_KEY` for code scans.
- `GRIT_API_TOKEN` only for pipelines that post merge request notes.

Do not pass secrets in generic webhook payloads because PipelineRun context can expose payload values in the UI. Use secure trigger properties, secure environment properties, or externalized secure properties instead.

### GRIT API token access

Create the GRIT PAT as a bot or service user if your governance model allows it. Give it the minimum project role needed to create merge request notes and select the `api` scope. Store it as `GRIT_API_TOKEN` in Secrets Manager.

## 10. Troubleshooting

### `promptfoo code-scans run` fails with an auth error

`promptfoo code-scans run` requires `PROMPTFOO_API_KEY` outside hosted GitHub Action flows. Confirm the secret exists in Secrets Manager and is mapped to the Tekton parameter or environment variable used by the task.

### The scan compares against the wrong branch

Fetch the target branch before running the scan and pass `--base` explicitly. For merge request triggers, map `TARGET_BRANCH` from the merge request event payload instead of hard-coding `main`.

### No merge request note appears

Confirm:

- `GRIT_PROJECT_ID` is the numeric project ID from the GRIT/GitLab payload.
- `GRIT_MERGE_REQUEST_IID` is the merge request IID, not the global merge request ID.
- `GRIT_API_BASE_URL` matches your IBM Cloud region.
- `GRIT_API_TOKEN` has `api` scope and can access the project.
- The `curl --fail-with-body` output does not show a 401, 403, or 404 response.

### Secrets appear in logs

Do not echo secure properties. Do not include secrets in webhook payloads. Keep secrets in Secrets Manager-backed secure properties or externalized secure properties, and avoid shell debug mode (`set -x`) in steps that handle secret values.

### The trigger does not run for merge requests

Check the Git trigger event configuration, branch/pattern rules, draft merge request settings, and fork settings. If you use a CEL filter, inspect the raw PipelineRun event payload and verify that your CEL expression matches the actual payload fields.

## 11. Suggested repository layout

```text
.
├── promptfooconfig.yaml
├── package.json
├── .tekton
│   ├── promptfoo-eval.yaml
│   └── promptfoo-code-scan.yaml
└── README.md
```

## See also

- Promptfoo AWS CodeCommit Integration: https://www.promptfoo.dev/docs/integrations/aws-codecommit/
- Promptfoo CI/CD Integration: https://www.promptfoo.dev/docs/integrations/ci-cd/
- Promptfoo code scanning CLI docs: https://www.promptfoo.dev/docs/code-scanning/cli/
- IBM Cloud Continuous Delivery docs: https://cloud.ibm.com/docs/ContinuousDelivery
- IBM Cloud Git Repos and Issue Tracking docs: https://cloud.ibm.com/docs/ContinuousDelivery?topic=ContinuousDelivery-git_working
- IBM Cloud Secrets Manager docs: https://cloud.ibm.com/docs/secrets-manager
