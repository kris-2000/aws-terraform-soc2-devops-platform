// =============================================================================
// Jenkinsfile — Declarative Pipeline
// Stages: Checkout → SonarQube Analysis → Docker Build → Terraform Plan
// =============================================================================
pipeline {
    agent any

    environment {
        AWS_REGION      = 'ap-south-1'
        DOCKER_IMAGE    = 'krishnajune2000/hospital-app'
        SONAR_PROJECT   = 'aws-terraform-soc2-devops-platform'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        // ---------------------------------------------------------------
        // Stage 1: Checkout
        // ---------------------------------------------------------------
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branch: ${env.BRANCH_NAME} | Build: ${env.BUILD_NUMBER}"
            }
        }

        // ---------------------------------------------------------------
        // Stage 2: SonarQube Analysis
        // ---------------------------------------------------------------
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        sonar-scanner \
                          -Dsonar.projectKey=${SONAR_PROJECT} \
                          -Dsonar.sources=app,scripts,terraform,k8s \
                          -Dsonar.python.version=3.12
                    '''
                }
            }
        }

        // ---------------------------------------------------------------
        // Stage 3: Docker Build & Test
        // ---------------------------------------------------------------
        stage('Docker Build & Test') {
            steps {
                sh '''
                    echo "Building Docker image..."
                    docker build -t ${DOCKER_IMAGE}:${BUILD_NUMBER} ./app
                    docker tag ${DOCKER_IMAGE}:${BUILD_NUMBER} ${DOCKER_IMAGE}:latest

                    echo "Running container health test..."
                    docker run -d --name hospital-test-${BUILD_NUMBER} \
                        -p 8001:8000 ${DOCKER_IMAGE}:latest
                    sleep 5

                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/health)
                    docker stop hospital-test-${BUILD_NUMBER}
                    docker rm hospital-test-${BUILD_NUMBER}

                    if [ "$STATUS" != "200" ]; then
                        echo "FAIL: Health check returned $STATUS"
                        exit 1
                    fi
                    echo "PASS: Health check returned 200"
                '''
            }
        }

        // ---------------------------------------------------------------
        // Stage 4: Terraform Plan
        // ---------------------------------------------------------------
        stage('Terraform Plan') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials']]) {
                    dir('terraform') {
                        sh '''
                            terraform init -backend=false
                            terraform validate
                            terraform plan -var="db_password=PLACEHOLDER" -no-color
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline PASSED — Build #${env.BUILD_NUMBER} is clean and ready."
        }
        failure {
            echo "Pipeline FAILED — Check SonarQube gate or Docker health test."
            // Add emailext or Slack notification here in production
        }
        always {
            cleanWs()
        }
    }
}
