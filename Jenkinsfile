/* groovylint-disable CompileStatic, GStringExpressionWithinString, LineLength, NestedBlockDepth, DuplicateListLiteral, DuplicateStringLiteral, DuplicateNumberLiteral, NoDef, VariableTypeRequired, UnnecessaryGetter, Instanceof */
pipeline {
  agent any

  parameters {
    choice(name: 'ENV', choices: ['stage', 'prod'], description: 'Target environment')
    choice(name: 'CreateCAB', choices: ['No', 'Yes'], description: 'Create a new ServiceNow change request')
    choice(
      name: 'ChangeType',
      choices: ['normal', 'expedited', 'emergency'],
      description: 'ServiceNow change type when creating a new ticket'
    )
    string(name: 'Change', defaultValue: '', description: 'Existing ServiceNow change ticket ID (example: CHG000123)')
    string(
      name: 'SNOW_SERVICE_NAME',
      defaultValue: 'APIM-Party-Reference',
      description: 'Service name passed to createSNOWChange'
    )
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 60, unit: 'MINUTES')
  }

  // groovylint-disable GStringExpressionWithinString
  environment {
    ARM_USERNAME = credentials('azure-username')
    ARM_PASSWORD = credentials('azure-password')
    TF_INPUT                  = 'false'
    TF_IN_AUTOMATION          = 'true'
    TF_DIR                    = 'terraform'
    RESOURCE_GROUP_NAME_CRED  = 'rg-apim-demo'
    APIM_NAME_CRED            = 'my--party-apim-demo'
    ARM_SUBSCRIPTION_ID        = '5c617d29-4760-465d-8453-3dca268072eb'
    ARM_TENANT_ID              = '220fb4d0-cb02-4bc9-8d8a-8f85cf1c9161'
  }
  // groovylint-enable GStringExpressionWithinString

  stages {
    stage('Preflight: Tooling') {
      steps {
        bat '''
          echo [Preflight] Checking required tools...
          where docker >nul 2>nul || where node >nul 2>nul
          if %ERRORLEVEL% NEQ 0 (
            echo ERROR: Need Docker or Node to run Redocly CLI.
            exit /b 1
          )
          where terraform >nul 2>nul
          if %ERRORLEVEL% NEQ 0 (
            echo ERROR: Terraform not installed.
            exit /b 1
          )
          echo [Preflight] OK
        '''
      }
    }

    stage('Resolve ENV & Credentials') {
      steps {
        script {
          env.TF_ENV = params.ENV?.trim() ?: (env.BRANCH_NAME == 'main' ? 'prod' : 'stage')
          echo "Selected ENV: ${env.TF_ENV}"
          echo "Change management enabled: ${env.TF_ENV == 'prod'}"
        }
      }
    }

    stage('Checkout') {
      steps {
        checkout scm
        bat '''
          echo Repo root:
          dir
          echo.
          echo API dir:
          if exist api dir api
        '''
      }
    }
    stage('Bundle OpenAPI (multi-API)') {
      steps {
        bat '''
          if not exist build\\api-bundled mkdir build\\api-bundled
          for %%f in (api\\* v*.yaml) do (
            if exist "%%f" (
              echo [Bundle] Processing %%f
              npx -y @redocly/cli@latest bundle "%%f" --ext yaml -o "build\\api-bundled\\%%~nxf"
            )
          )
          echo [Bundle] Results:
          dir build\\api-bundled
        '''
      }
    }

    stage('Bundle validation (Redocly)') {
      steps {
        bat '''
            dir /b build\\api-bundled\\*.yaml > specs_list.txt
            for /F "delims=" %%f in (specs_list.txt) do (
              echo [Lint] Running Redocly against "%%f"
              npx -y @redocly/cli@latest lint --config redocly.yaml --format json "build\\api-bundled\\%%f" >> redocly-report.json
            )
          del specs_list.txt
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'redocly-report.json', allowEmptyArchive: true
        }
      }
    }

    stage('Terraform Init/Validate') {
      steps {
        bat '''
          echo [Init] Using TF_DIR=%TF_DIR%
          terraform -chdir="%TF_DIR%" init -reconfigure -input=false -no-color
          terraform -chdir="%TF_DIR%" fmt -check -diff -recursive -no-color
          if %ERRORLEVEL% NEQ 0 (
            echo [Terraform] fmt issues detected
            exit /b %ERRORLEVEL%
          )
          terraform -chdir="%TF_DIR%" validate -no-color
        '''
      }
    }

    stage('Terraform Plan') {
      steps {
        bat '''
          terraform -chdir="%TF_DIR%" plan -input=false -no-color -var="resource_group_name=%RESOURCE_GROUP_NAME_CRED%" -var="api_management_name=%APIM_NAME_CRED%" -out=tfplan.out
          if not exist "%TF_DIR%\\tfplan.out" (
            echo ERROR: Plan command finished but plan file missing at %TF_DIR%\\tfplan.out
            exit /b 1
          )
          echo [Plan] Plan file created at %TF_DIR%\\tfplan.out
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: '%TF_DIR%/tfplan.out', fingerprint: true, allowEmptyArchive: false
        }
      }
    }

    stage('Terraform Apply') {
      steps {
        bat '''
          set PLAN_FILE=tfplan.out
          set PLAN_FILE_PATH=%TF_DIR%\\%PLAN_FILE%
          echo [Apply] Workspace: %CD%
          echo [Apply] TF_DIR=%TF_DIR%
          echo [Apply] Expecting plan at %PLAN_FILE_PATH%
          if not exist "%PLAN_FILE_PATH%" (
            echo ERROR: Plan file not found at %PLAN_FILE_PATH%
            dir %TF_DIR%
            exit /b 1
          )
          echo [Apply] Applying plan...
          terraform -chdir="%TF_DIR%" apply -input=false -no-color -auto-approve "%PLAN_FILE%"
          if %ERRORLEVEL% NEQ 0 (
            echo ERROR: Apply failed. Automatic targeted rollback is disabled by policy.
            echo Please perform controlled manual recovery using approved runbook.
            exit /b 1
          )
          echo [Apply] Deployment successful
        '''
      }
    }
    }

  post {
    success { echo "Build succeeded. ${BUILD_URL}" }
    failure { echo "Build failed: ${BUILD_URL}" }
    always {
      bat '''
        for /r %%f in (tfplan.out) do del "%%f"
        echo [Cleanup] Removed tfplan files
      '''
    }
  }
}
