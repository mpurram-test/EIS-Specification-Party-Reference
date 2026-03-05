/* groovylint-disable CompileStatic, DuplicateStringLiteral */
pipeline {
  agent { label 'dev' }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  environment {
    TF_INPUT         = 'false'
    TF_IN_AUTOMATION = 'true'
    TF_DIR                 = 'terraform'
    RESOURCE_GROUP_NAME_CRED = credentials('stage-apim-rg-name')
    APIM_NAME_CRED           = credentials('stage-apim-apim-name')
    ARM_SUBSCRIPTION_ID      = credentials('stage-apim-azure-subscription-id')
    ARM_CLIENT_ID            = credentials('stage-apim-azure-client')
    ARM_CLIENT_SECRET        = credentials('stage-apim-azure-secret')
    ARM_TENANT_ID            = credentials('stage-apim-azure-tenant')
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
          #This ensures the 'jenkins' user can read the files created by the bundler.
          chown -R jenkins:jenkins build/
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
          #!/usr/bin/env bash
          set -e

          echo "[Terraform] Init in: $TF_DIR"
          terraform -chdir="$TF_DIR" init -input=false -no-color

          set +e
          FMT_OUTPUT=$(terraform -chdir="$TF_DIR" fmt -check -diff -recursive -no-color 2>&1)
          FMT_STATUS=$?
          set -e

          if [ "$FMT_STATUS" -ne 0 ]; then
            echo "[Terraform] Formatting issues detected (exit $FMT_STATUS)."
            echo "----- BEGIN terraform fmt diff -----"
            echo "$FMT_OUTPUT"
            echo "----- END terraform fmt diff -----"
            echo "Fix locally with:"
            echo "  terraform -chdir=\"$TF_DIR\" fmt -recursive"
            exit "$FMT_STATUS"   # usually 3 for fmt issues
          fi

          terraform -chdir="$TF_DIR" validate -no-color
        '''
      }
    }

    stage('Terraform Plan') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          echo "[Plan] Checking bundled specs exist at: $WORKSPACE/build/api-bundled"
          ls -la "$WORKSPACE/build/api-bundled" || { echo "ERROR: No bundled specs found"; exit 1; }

          terraform -chdir="$TF_DIR" plan -input=false -no-color -parallelism=1 \
            -var="resource_group_name=$RESOURCE_GROUP_NAME_CRED" \
            -var="api_management_name=$APIM_NAME_CRED" \
            -out=tfplan.out
        '''

        stash name: 'tfplan', includes: 'terraform/tfplan.out', useDefaultExcludes: false
      }
      post {
        always {
          archiveArtifacts artifacts: 'terraform/tfplan.out', fingerprint: true, allowEmptyArchive: false
        }
      }
    }

    stage('Approve Apply') {
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: 'Approve Terraform apply to APIM?', ok: 'Apply'
        }
      }
    }

    stage('Terraform Apply') {
      steps {
        unstash 'tfplan'

        sh '''
          #!/usr/bin/env bash
          set -e

          echo "[Apply] Applying plan..."
          terraform -chdir="$TF_DIR" apply -input=false -no-color -parallelism=1 -auto-approve \
            -var="resource_group_name=$RESOURCE_GROUP_NAME_CRED" \
            -var="api_management_name=$APIM_NAME_CRED" \
            tfplan.out
        '''
      }
    }

    stage('Verify APIM Deployment') {
      steps {
        sh '''
          #!/usr/bin/env bash
          set -e

          echo "[Verify] Running post-apply drift check..."

          set +e
          terraform -chdir="$TF_DIR" plan -input=false -no-color -detailed-exitcode -parallelism=1 \
            -var="resource_group_name=$RESOURCE_GROUP_NAME_CRED" \
            -var="api_management_name=$APIM_NAME_CRED"
          VERIFY_EXIT=$?
          set -e

          if [ "$VERIFY_EXIT" -eq 0 ]; then
            echo "[Verify] No drift detected. Deployment verification passed."
            exit 0
          fi

          if [ "$VERIFY_EXIT" -eq 2 ]; then
            echo "[Verify] Drift detected after apply."
            echo "[Verify] Expected no pending changes immediately after deployment."
            exit 1
          fi

          echo "[Verify] Terraform verification plan failed with exit code $VERIFY_EXIT"
          exit "$VERIFY_EXIT"
        '''
      }
    }
  }

  post {
    success { echo "Build succeeded. ${BUILD_URL}" }
    failure { echo "Build failed: ${BUILD_URL}" }
    always {
      sh '''
        #!/usr/bin/env bash
        set +e
        rm -f terraform/tfplan.out terraform/post_apply_verify.out
        echo "[Cleanup] Removed temporary Terraform plan files"
      '''
    }
  }
}
