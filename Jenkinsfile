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
          set -e
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
        sh 'echo "Repo root:" && ls -la'
        sh 'echo "\\nAPI dir:" && ls -la api || { echo "WARNING: api/ not found"; true; }'
      }
    }

    stage('Bundle OpenAPI (multi-API)') {
      steps {
        sh '''
          set -e
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

    stage('Redocly Lint (bundled - fail on errors)') {
      steps {
        script {
          if (sh(script: 'ls build/api-bundled/*\\ v*.yaml >/dev/null 2>&1', returnStatus: true) != 0) {
            error "No bundled versioned specs found in build/api-bundled. Aborting."
          }
          def cmdDocker = 'docker run --rm -v "$PWD":/spec redocly/cli lint "build/api-bundled/* v*.yaml"'
          def cmdNPX    = 'npx -y @redocly/cli@latest lint "build/api-bundled/* v*.yaml"'

          if (sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0) {
            sh cmdDocker
          } else if (sh(script: 'command -v node >/dev/null 2>&1', returnStatus: true) == 0) {
            sh cmdNPX
          } else {
            error "Neither Docker nor Node found to run Redocly CLI."
          }
        }
      }
    }

    stage('Terraform Init/Validate') {
      steps {
        sh '''
          set -e
          echo "[Terraform] Running in: ${TF_DIR:-.}"
          terraform -chdir="${TF_DIR:-.}" init -input=false
          terraform -chdir="${TF_DIR:-.}" fmt -check
          terraform -chdir="${TF_DIR:-.}" validate
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
            set -e
            echo "[Plan] Checking bundled specs exist at: ${WORKSPACE}/build/api-bundled"
            ls -la "${WORKSPACE}/build/api-bundled" \
              || { echo "ERROR: No bundled specs found"; exit 1; }

            terraform -chdir="${TF_DIR:-.}" plan -input=false \
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
          set -e
          echo "[Apply] Applying plan..."
          terraform -chdir="${TF_DIR:-.}" apply -input=false -auto-approve tfplan.dev.out
        '''
      }
    }
  }

  post {
    success { echo "Build succeeded. ${BUILD_URL}" }
    failure { echo "Build failed: ${BUILD_URL}" }
  }
}