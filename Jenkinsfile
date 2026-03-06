/* groovylint-disable CompileStatic */

// Constants to eliminate duplicate string literals
@Field static final String PROD_ENV = 'prod'
@Field static final List SUPPORTED_ENVS = ['stage', PROD_ENV]
@Field static final String ARM_SUBSCRIPTION_ID = 'ARM_SUBSCRIPTION_ID'
@Field static final String ARM_CLIENT_ID = 'ARM_CLIENT_ID'
@Field static final String ARM_CLIENT_SECRET = 'ARM_CLIENT_SECRET'
@Field static final String ARM_TENANT_ID = 'ARM_TENANT_ID'
@Field static final String RESOURCE_GROUP_NAME_CRED = 'RESOURCE_GROUP_NAME_CRED'
@Field static final String APIM_NAME_CRED = 'APIM_NAME_CRED'

pipeline {
  agent { label 'dev' }

  parameters {
    choice(name: 'ENV', choices: SUPPORTED_ENVS, description: 'Target environment')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  environment {
    TF_INPUT         = 'false'
    TF_IN_AUTOMATION = 'true'
    TF_DIR           = 'terraform'
  }

  stages {
    stage('Preflight: Tooling') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e
          echo "[Preflight] Checking required tools..."

          if ! command -v docker >/dev/null 2>&1 && \
             (! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1); then
            echo "ERROR: Need Docker or Node+npx to run Redocly CLI."
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
          validateEnvironment()
          configureCredentials()
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

    /*
    stage('Redocly Lint (bundled)') {
      steps {
        script {
          // STEP 1 — verify files exist
          if (sh(script: 'ls build/api-bundled/*\\ v*.yaml >/dev/null 2>&1', returnStatus: true) != 0) {
            error 'No bundled specs found. Aborting.'
          }

          // STEP 2 — safe file list
          String[] files = sh(script: 'ls build/api-bundled/*\\ v*.yaml', returnStdout: true)
            .trim().split('\\r?\\n')

          // STEP 3 — quote filenames (because they contain spaces)
          String filesQuoted = files.collect { f -> "\"${f}\"" }.join(' ')

          // STEP 4 — choose Redocly runner
          boolean hasDocker = (sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0)

          String lintCmdDocker = """
            docker run --rm -w /spec -v "$PWD":/spec redocly/cli \
            lint --format json ${filesQuoted} \
            | tee redocly-report.json
          """

          String lintCmdNPX = """
            npx -y @redocly/cli@latest \
            lint --config redocly.yaml --format json ${filesQuoted} \
            | tee redocly-report.json
          """

          // STEP 5 — run lint
          int exitCode = sh(script: hasDocker ? lintCmdDocker : lintCmdNPX,
            returnStatus: true)

          // STEP 6 — print by-rule summary
          String text = readFile('redocly-report.json')
          Object json = new groovy.json.JsonSlurper().parseText(text)
          List reports = (json instanceof List) ? (List) json : [json]
          List problems = reports.collectMany { r -> r.problems ?: [] }
          Map byRule = problems.groupBy { p -> p.ruleId ?: p.rule }
            .collectEntries { rule, list -> [(rule ?: 'unknown'): list.size()] }

          echo '========= Redocly Summary ========='
          echo byRule.sort { e -> -e.value }.toString()
          echo '=================================='

          // STEP 7 — archive + fail only on real errors
          archiveArtifacts artifacts: 'redocly-report.json', allowEmptyArchive: false

          if (exitCode != 0) {
            error 'Redocly lint failed. See redocly-report.json.'
          }
        }
      }
    }
    */

    stage('Terraform Init/Validate') {
      steps {
        withCredentials([
          string(credentialsId: env.CRED_AZURE_SUBSCRIPTION_ID, variable: ARM_SUBSCRIPTION_ID),
          string(credentialsId: env.CRED_AZURE_CLIENT_ID, variable: ARM_CLIENT_ID),
          string(credentialsId: env.CRED_AZURE_CLIENT_SECRET, variable: ARM_CLIENT_SECRET),
          string(credentialsId: env.CRED_AZURE_TENANT_ID, variable: ARM_TENANT_ID)
        ]) {
          sh """
            set -e
            echo "[Init] Using TF_DIR=${TF_DIR}"
            terraform -chdir="${TF_DIR}" init -backend-config="${BACKEND_FILE}" -lock-timeout=5m -input=false -no-color

            set +e
            FMT_OUTPUT=\$(terraform -chdir="${TF_DIR}" fmt -check -diff -recursive -no-color 2>&1)
            FMT_STATUS=\$?
            set -e
            if [ "\${FMT_STATUS}" -ne 0 ]; then
              echo "[Terraform] fmt issues detected:"
              echo "\${FMT_OUTPUT}"
              exit \${FMT_STATUS}
            fi

            terraform -chdir="${TF_DIR}" validate -no-color
          """
        }
      }
    }

    stage('Terraform Plan') {
      steps {
        withCredentials([
          string(credentialsId: env.CRED_RG_ID, variable: RESOURCE_GROUP_NAME_CRED),
          string(credentialsId: env.CRED_APIM_NAME_ID, variable: APIM_NAME_CRED),
          string(credentialsId: env.CRED_AZURE_SUBSCRIPTION_ID, variable: ARM_SUBSCRIPTION_ID),
          string(credentialsId: env.CRED_AZURE_CLIENT_ID, variable: ARM_CLIENT_ID),
          string(credentialsId: env.CRED_AZURE_CLIENT_SECRET, variable: ARM_CLIENT_SECRET),
          string(credentialsId: env.CRED_AZURE_TENANT_ID, variable: ARM_TENANT_ID)
        ]) {
          sh """
            #!/usr/bin/env bash
            set -e
            set +e
            terraform -chdir="${TF_DIR}" plan -detailed-exitcode -lock-timeout=5m -input=false -no-color \
              -var="resource_group_name=${RESOURCE_GROUP_NAME_CRED}" \
              -var="api_management_name=${APIM_NAME_CRED}" \
              -out=tfplan.out
            PLAN_STATUS=\$?
            set -e

            if [ "${PLAN_STATUS}" -eq 1 ]; then
              echo "ERROR: Terraform plan failed"
              exit 1
            fi

            if [ "${PLAN_STATUS}" -eq 0 ]; then
              echo "[Plan] No infrastructure changes detected"
              rm -f "${TF_DIR}/has_changes.flag"
              exit 0
            fi

            touch "${TF_DIR}/has_changes.flag"

            PLAN_FILE_PATH="${TF_DIR}/tfplan.out"
            if [ ! -f "\${PLAN_FILE_PATH}" ]; then
              echo "ERROR: Plan command finished but plan file missing at \${PLAN_FILE_PATH}"
              exit 1
            fi
            echo "[Plan] Plan file created at \${PLAN_FILE_PATH}"
          """
        }
      }
      post {
        always {
          archiveArtifacts artifacts: "${TF_DIR}/tfplan.out", fingerprint: true, allowEmptyArchive: false
        }
      }
    }

    stage('Production Approval') {
      when {
        expression { env.TF_ENV == PROD_ENV }
      }
      steps {
        input message: "Approve Terraform apply to ${env.TF_ENV}?", ok: 'Deploy'
      }
    }

    stage('Terraform Apply') {
      steps {
        withCredentials([
          string(credentialsId: env.CRED_RG_ID, variable: RESOURCE_GROUP_NAME_CRED),
          string(credentialsId: env.CRED_APIM_NAME_ID, variable: APIM_NAME_CRED),
          string(credentialsId: env.CRED_AZURE_SUBSCRIPTION_ID, variable: ARM_SUBSCRIPTION_ID),
          string(credentialsId: env.CRED_AZURE_CLIENT_ID, variable: ARM_CLIENT_ID),
          string(credentialsId: env.CRED_AZURE_CLIENT_SECRET, variable: ARM_CLIENT_SECRET),
          string(credentialsId: env.CRED_AZURE_TENANT_ID, variable: ARM_TENANT_ID)
        ]) {
          sh """
            #!/usr/bin/env bash
            set -e

            PLAN_FILE="tfplan.out"
            PLAN_FILE_PATH="${TF_DIR}/\${PLAN_FILE}"
            echo "[Apply] Workspace: \$(pwd)"
            echo "[Apply] TF_DIR=${TF_DIR}"

            if [ ! -f "${TF_DIR}/has_changes.flag" ]; then
              echo "[Apply] No changes detected in plan stage; skipping apply"
              exit 0
            fi

            echo "[Apply] Expecting plan at \${PLAN_FILE_PATH}"
            if [ ! -f "\${PLAN_FILE_PATH}" ]; then
              echo "ERROR: Plan file not found at \${PLAN_FILE_PATH}"
              ls -la "${TF_DIR}" || true
              exit 1
            fi

            echo "[Apply] Applying plan..."
            if ! terraform -chdir="${TF_DIR}" apply -lock-timeout=5m \
              -input=false -no-color -auto-approve "\${PLAN_FILE}"; then
              echo "ERROR: Apply failed. Automatic targeted rollback is disabled by policy."
              echo "Please perform controlled manual recovery using approved runbook."
              exit 1
            fi

            rm -f "${TF_DIR}/has_changes.flag"
            echo "[Apply] Deployment successful"
          """
        }
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

// Helper methods to reduce nesting and improve readability
void validateEnvironment() {
  env.TF_ENV = params.ENV?.trim()
  if (!env.TF_ENV) {
    error 'ENV build parameter is required (for example: stage or prod)'
  }
  if (!SUPPORTED_ENVS.contains(env.TF_ENV)) {
    error "Unsupported ENV=${env.TF_ENV}. Expected one of: ${SUPPORTED_ENVS.join(', ')}"
  }
}

void configureCredentials() {
  String credPrefix = env.TF_ENV
  env.BACKEND_FILE = "backend-${env.TF_ENV}.tfvars"
  env.with {
    CRED_RG_ID = "${credPrefix}-apim-rg-name"
    CRED_APIM_NAME_ID = "${credPrefix}-apim-apim-name"
    CRED_AZURE_SUBSCRIPTION_ID = "${credPrefix}-apim-azure-subscription-id"
    CRED_AZURE_CLIENT_ID = "${credPrefix}-apim-azure-client"
    CRED_AZURE_CLIENT_SECRET = "${credPrefix}-apim-azure-secret"
    CRED_AZURE_TENANT_ID = "${credPrefix}-apim-azure-tenant"
  }
  echo "Computed ENV=${env.TF_ENV} TF_DIR=${env.TF_DIR} BACKEND_FILE=${env.BACKEND_FILE}"
}
