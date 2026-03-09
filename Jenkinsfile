/* groovylint-disable CompileStatic, GStringExpressionWithinString */
pipeline {
  agent { label 'dev' }

  parameters {
    choice(name: 'ENV', choices: ['stage', 'prod'], description: 'Target environment')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  // groovylint-disable GStringExpressionWithinString
  environment {
    TF_INPUT                  = 'false'
    TF_IN_AUTOMATION          = 'true'
    TF_DIR                    = 'terraform'
    RESOURCE_GROUP_NAME_CRED  = credentials("${params.ENV}-apim-rg-name")
    APIM_NAME_CRED            = credentials("${params.ENV}-apim-apim-name")
    ARM_SUBSCRIPTION_ID        = credentials("${params.ENV}-apim-azure-subscription-id")
    ARM_CLIENT_ID              = credentials("${params.ENV}-apim-azure-client")
    ARM_CLIENT_SECRET          = credentials("${params.ENV}-apim-azure-secret")
    ARM_TENANT_ID              = credentials("${params.ENV}-apim-azure-tenant")
  }
  // groovylint-enable GStringExpressionWithinString

  stages {
    stage('Preflight: Tooling') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e
          echo "[Preflight] Checking required tools..."

          if ! command -v docker >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
            echo "ERROR: Need Docker or Node to run Redocly CLI."
            exit 1
          fi

          if ! command -v terraform >/dev/null 2>&1; then
            echo "ERROR: Terraform not installed."
            exit 1
          fi

          echo "[Preflight] OK"
        '''
      }
    }

    stage('Resolve ENV & Credentials') {
      steps {
        script {
          env.TF_ENV = params.ENV?.trim() ?: (env.BRANCH_NAME == 'main' ? 'prod' : 'stage')
          env.BACKEND_TFVARS = "backend-${env.TF_ENV}.tfvars"
          echo "Selected ENV: ${env.TF_ENV}"
          echo "Backend config file: ${env.BACKEND_TFVARS}"
        }
      }
    }

    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          #!/usr/bin/env bash
          set -e
          echo "Repo root:" && ls -la
          echo ""
          echo "API dir:" && ls -la api || true
        '''
      }
    }

    stage('Bundle OpenAPI (multi-API)') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          mkdir -p build/api-bundled

          # Bundle only files like "My API v1.yaml" (space ' v' then version)
          for f in api/*\\ v*.yaml; do
            [ -f "$f" ] || continue

            base="$(basename "$f")"
            echo "[Bundle] Processing $f"

            if command -v docker >/dev/null 2>&1; then
              docker run --rm -v "$PWD":/spec redocly/cli \
                bundle "$f" --ext yaml -o "build/api-bundled/$base"
            else
              npx -y @redocly/cli@latest \
                bundle "$f" --ext yaml -o "build/api-bundled/$base"
            fi
          done
          # Best effort only: some agents/containers do not allow chown.
          if command -v chown >/dev/null 2>&1 && chown -R jenkins:jenkins build/ 2>/dev/null; then
            echo "[Bundle] Ownership updated to jenkins:jenkins"
          else
            echo "[Bundle] Skipping chown (not supported/allowed on this agent)"
          fi
          echo "[Bundle] Results:"
          ls -la build/api-bundled
        '''
      }
    }

    // stage('Redocly Lint (bundled)') {
    //   steps {
    //     script {

    //       // STEP 1 — verify files exist
    //       if (sh(script: 'ls build/api-bundled/*\\ v*.yaml >/dev/null 2>&1', returnStatus: true) != 0) {
    //         error "No bundled specs found. Aborting."
    //       }

    //       // STEP 2 — safe file list
    //       def files = sh(script: 'ls build/api-bundled/*\\ v*.yaml', returnStdout: true)
    //                     .trim().split('\\r?\\n')

    //       // STEP 3 — quote filenames (because they contain spaces)
    //       def filesQuoted = files.collect { "\"${it}\"" }.join(' ')

    //       // STEP 4 — choose Redocly runner
    //       def hasDocker = (sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0)

    //       def lintCmdDocker = """
    //         docker run --rm -w /spec -v "$PWD":/spec redocly/cli \
    //         lint --format json ${filesQuoted} \
    //         | tee redocly-report.json
    //       """

    //       def lintCmdNPX = """
    //         npx -y @redocly/cli@latest \
    //         lint --config redocly.yaml --format json ${filesQuoted} \
    //         | tee redocly-report.json
    //       """

    //       // STEP 5 — run lint
    //       def exitCode = sh(script: hasDocker ? lintCmdDocker : lintCmdNPX,
    //                         returnStatus: true)

    //       // STEP 6 — print by-rule summary
    //       def text = readFile('redocly-report.json')
    //       def json = new groovy.json.JsonSlurper().parseText(text)
    //       def reports = (json instanceof List) ? json : [json]
    //       def problems = reports.collectMany { it.problems ?: [] }
    //       def byRule = problems.groupBy { it.ruleId ?: it.rule }
    //                            .collectEntries { rule, list -> [(rule ?: 'unknown'): list.size()] }

    //       echo "========= Redocly Summary ========="
    //       echo byRule.sort { -it.value }.toString()
    //       echo "=================================="

    //       // STEP 7 — archive + fail only on real errors
    //       archiveArtifacts artifacts: 'redocly-report.json', allowEmptyArchive: false

    //       if (exitCode != 0) {
    //         error "Redocly lint failed. See redocly-report.json."
    //       }
    //     }
    //   }
    // }

    stage('Terraform Init/Validate') {
      steps {
        sh '''
          set -e

          echo "[Init] Using TF_DIR=${TF_DIR}"
          terraform -chdir="${TF_DIR}" init -backend-config="${BACKEND_TFVARS}" -input=false -no-color

          set +e
          FMT_OUTPUT=$(terraform -chdir="${TF_DIR}" fmt -check -diff -recursive -no-color 2>&1)
          FMT_STATUS=$?
          set -e
          if [ "${FMT_STATUS}" -ne 0 ]; then
            echo "[Terraform] fmt issues detected:"
            echo "${FMT_OUTPUT}"
            exit ${FMT_STATUS}
          fi

          terraform -chdir="${TF_DIR}" validate -no-color
        '''
      }
    }

    stage('Terraform Plan') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          terraform -chdir="${TF_DIR}" plan -input=false -no-color \
            -var="resource_group_name=${RESOURCE_GROUP_NAME_CRED}" \
            -var="api_management_name=${APIM_NAME_CRED}" \
            -out=tfplan.out

          PLAN_FILE_PATH="${TF_DIR}/tfplan.out"
          if [ ! -f "${PLAN_FILE_PATH}" ]; then
            echo "ERROR: Plan command finished but plan file missing at ${PLAN_FILE_PATH}"
            exit 1
          fi
          echo "[Plan] Plan file created at ${PLAN_FILE_PATH}"
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: "${TF_DIR}/tfplan.out", fingerprint: true, allowEmptyArchive: false
        }
      }
    }

    stage('Terraform Apply') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          PLAN_FILE="tfplan.out"
          PLAN_FILE_PATH="${TF_DIR}/${PLAN_FILE}"
          echo "[Apply] Workspace: $(pwd)"
          echo "[Apply] TF_DIR=${TF_DIR}"
          echo "[Apply] Expecting plan at ${PLAN_FILE_PATH}"
          if [ ! -f "${PLAN_FILE_PATH}" ]; then
            echo "ERROR: Plan file not found at ${PLAN_FILE_PATH}"
            ls -la "${TF_DIR}" || true
            exit 1
          fi

          echo "[Apply] Applying plan..."
          if ! terraform -chdir="${TF_DIR}" apply -input=false -no-color -auto-approve "${PLAN_FILE}"; then
            echo "ERROR: Apply failed. Automatic targeted rollback is disabled by policy."
            echo "Please perform controlled manual recovery using approved runbook."
            exit 1
          fi

          echo "[Apply] Deployment successful"
        '''
      }
    }
  }

  post {
    success { echo "Build succeeded. ${BUILD_URL}" }
    failure { echo "Build failed: ${BUILD_URL}" }
    always {
      sh '''
        find . -name "tfplan.out" -delete
        echo "[Cleanup] Removed tfplan files"
      '''
    }
  }
}
