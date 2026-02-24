pipeline {
  agent { label 'dev' }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  environment {
    TF_INPUT                 = 'false'
    TF_IN_AUTOMATION         = 'true'
    RESOURCE_GROUP_NAME_CRED = credentials('stage-apim-rg-name')
    APIM_NAME_CRED           = credentials('stage-apim-apim-name')
    TF_DIR                   = '.'
  }

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


    stage('Pull Source Control') {
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

          # Pattern only matches versioned API files directly under /api/
          # It will NOT match anything in api/Definitions/ — so no filter needed.
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

          echo "[Bundle] Results:"
          ls -la build/api-bundled
        '''
      }
    }


    stage('Redocly Lint (bundled)') {
      steps {
        script {

          // STEP 1 — verify files exist
          if (sh(script: 'ls build/api-bundled/*\\ v*.yaml >/dev/null 2>&1', returnStatus: true) != 0) {
            error "No bundled specs found. Aborting."
          }

          // STEP 2 — safe file list
          def files = sh(script: 'ls build/api-bundled/*\\ v*.yaml', returnStdout: true)
                        .trim().split('\\r?\\n')

          // STEP 3 — quote filenames (because they contain spaces)
          def filesQuoted = files.collect { "\"${it}\"" }.join(' ')

          // STEP 4 — choose Redocly runner
          def hasDocker = (sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0)

          def lintCmdDocker = """
            docker run --rm -w /spec -v "$PWD":/spec redocly/cli \
            lint --config redocly.yaml --format json ${filesQuoted} \
            | tee redocly-report.json
          """

          def lintCmdNPX = """
            npx -y @redocly/cli@latest \
            lint --config redocly.yaml --format json ${filesQuoted} \
            | tee redocly-report.json
          """

          // STEP 5 — run lint
          def exitCode = sh(script: hasDocker ? lintCmdDocker : lintCmdNPX,
                            returnStatus: true)

          // STEP 6 — print by-rule summary
          def text = readFile('redocly-report.json')
          def json = new groovy.json.JsonSlurper().parseText(text)
          def reports = (json instanceof List) ? json : [json]
          def problems = reports.collectMany { it.problems ?: [] }
          def byRule = problems.groupBy { it.ruleId ?: it.rule }
                               .collectEntries { rule, list -> [(rule ?: 'unknown'): list.size()] }

          echo "========= Redocly Summary ========="
          echo byRule.sort { -it.value }.toString()
          echo "=================================="

          // STEP 7 — archive + fail only on real errors
          archiveArtifacts artifacts: 'redocly-report.json', allowEmptyArchive: false

          if (exitCode != 0) {
            error "Redocly lint failed. See redocly-report.json."
          }
        }
      }
    }

    stage('Terraform Init/Validate') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          echo "[Terraform] Running in: ${TF_DIR:-.}"

          # Init with clean logs
          terraform -chdir="${TF_DIR:-.}" init -input=false -no-color
          set +e
          FMT_OUTPUT=$(terraform -chdir="${TF_DIR:-.}" fmt -check -diff -recursive -no-color 2>&1)
          FMT_STATUS=$?
          set -e

          if [ "${FMT_STATUS}" -ne 0 ]; then
            echo "[Terraform] Formatting issues detected (exit ${FMT_STATUS})."
            echo "----- BEGIN terraform fmt diff -----"
            echo "${FMT_OUTPUT}"
            echo "----- END terraform fmt diff -----"
            echo "Fix locally with:"
            echo "  terraform -chdir=\\"${TF_DIR:-.}\\" fmt -recursive"
            exit "${FMT_STATUS}"   # usually 3 for fmt issues
          fi

          # Validate
          terraform -chdir="${TF_DIR:-.}" validate -no-color
        '''
      }
    }

    stage('Terraform Plan') {
      steps {
        withCredentials([
          string(credentialsId: 'stage-apim-azure-subscription-id', variable: 'ARM_SUBSCRIPTION_ID'),
          string(credentialsId: 'stage-apim-azure-client',          variable: 'ARM_CLIENT_ID'),
          string(credentialsId: 'stage-apim-azure-secret',          variable: 'ARM_CLIENT_SECRET'),
          string(credentialsId: 'stage-apim-azure-tenant',          variable: 'ARM_TENANT_ID')
        ]) {
          sh '''
            #!/usr/bin/env bash
            set -e

            echo "[Plan] Checking bundled specs exist at: ${WORKSPACE}/build/api-bundled"
            ls -la "${WORKSPACE}/build/api-bundled" || { echo "ERROR: No bundled specs found"; exit 1; }

            terraform -chdir="${TF_DIR:-.}" plan -input=false -no-color \
              -var="resource_group_name=${RESOURCE_GROUP_NAME_CRED}" \
              -var="api_management_name=${APIM_NAME_CRED}" \
              -out=tfplan.dev.out
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: '**/tfplan.dev.out', fingerprint: true
        }
      }
    }

    stage('Terraform Apply') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          echo "[Apply] Applying plan..."
          terraform -chdir="${TF_DIR:-.}" apply -input=false -no-color -auto-approve tfplan.dev.out
        '''
      }
    }
  }

  post {
    success { echo "Build succeeded. ${BUILD_URL}" }
    failure { echo "Build failed: ${BUILD_URL}" }
  }
}