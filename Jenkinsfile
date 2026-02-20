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
    RESOURCE_GROUP_NAME_CRED = credentials('stage-apim-rg-name')     // Secret Text
    APIM_NAME_CRED           = credentials('stage-apim-apim-name')   // Secret Text
    TF_DIR                   = '.'
  }

  stages {

    stage('Preflight: Tooling') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e
          set -x
          echo "[Preflight] Checking required tools on agent..."
          if ! command -v docker >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
            echo "ERROR: Need either Docker or Node on the agent to run Redocly CLI."
            exit 1
          fi
          if ! command -v terraform >/dev/null 2>&1; then
            echo "ERROR: Terraform is not installed on this agent."
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
          set -x
          echo "Repo root:" && ls -la
          echo ""
          echo "API dir:" && ls -la api || { echo "WARNING: api/ not found"; true; }
        '''
      }
    }

    stage('Bundle OpenAPI (multi-API)') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e
          set -x

          mkdir -p build/api-bundled

          # Only versioned files like "* v1.yaml", "* v2.yaml"; skip *Definitions*
          for f in api/*\\ v*.yaml; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            case "$base" in
              *Definitions* ) echo "Skipping definitions file: $f"; continue ;;
            esac

            echo "[Bundle] Processing $f"

            if command -v docker >/dev/null 2>&1; then
              docker run --rm -v "$PWD":/spec redocly/cli \
                bundle "$f" --ext yaml -o "build/api-bundled/$base"
            elif command -v node >/dev/null 2>&1; then
              npx -y @redocly/cli@latest bundle "$f" --ext yaml -o "build/api-bundled/$base"
            else
              echo "ERROR: Need Docker or Node to run Redocly CLI." >&2
              exit 1
            fi
          done

          echo "[Bundle] Bundled files:"
          ls -la build/api-bundled || true
        '''
      }
    }

    stage('Terraform Init/Validate') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e
          set -x

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
            set -x

            echo "[Plan] Checking bundled specs exist at: ${WORKSPACE}/build/api-bundled"
            ls -la "${WORKSPACE}/build/api-bundled" || { echo "ERROR: No bundled specs found"; exit 1; }

            terraform -chdir="${TF_DIR:-.}" plan -input=false -no-color \
              -var="resource_group_name=${RESOURCE_GROUP_NAME_CRED}" \
              -var="api_management_name=${APIM_NAME_CRED}" \
              -var="spec_folder=${WORKSPACE}/build/api-bundled" \
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
          set -x

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