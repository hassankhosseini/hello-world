appName = "hello-world"
githubCredentialID = "aram-github-account"
githubAccount = "aramalipoor"
githubRepo = "hello-world"

def deleteEverything(instanceName) {
  openshiftDeleteResourceByLabels(types: "is,bc,dc,svc,route", keys: "template", values: instanceName)
}

pipeline {
    options {
        // set a timeout of 20 minutes for this pipeline
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
    }
    agent {
      node {
        // spin up a slave pod to run this build on
        label 'base'
      }
    }
    stages {
        stage('preamble') {
            steps {
                script {
                    if (env.CHANGE_ID) {
                      instanceName = "${appName}-pr${env.CHANGE_ID}"
                    } else {
                      instanceName = "${appName}-${env.BRANCH_NAME}".replaceAll("/","-")
                    }

                    gitCommit = sh(returnStdout: true, script: "git rev-parse HEAD").trim()
                    gitShortCommit = sh(returnStdout: true, script: "git log -n 1 --pretty=format:'%h'").trim()

                    sh("printenv")

                    githubNotify status: "PENDING", context: "build", description: 'Starting pipeline', targetUrl: "${env.RUN_DISPLAY_URL}"
                    githubNotify status: "PENDING", context: "preview", description: 'Waiting for successful build'

                    openshift.withCluster() {
                        openshift.withProject() {
                            echo "Building, testing and deploying for ${instanceName} in project ${openshift.project()}"
                        }
                    }
                }
            }
        }
        stage('cleanup') {
            steps {
                githubNotify status: "PENDING", context: "build", description: 'Cleaning up old resources', targetUrl: "${env.RUN_DISPLAY_URL}"
                deleteEverything(instanceName)
            }
        }

        // Create a new app stack to fully build, deploy and serve this branch
        stage('create') {
            steps {
                githubNotify status: "PENDING", context: "build", description: 'Creating new resources', targetUrl: "${env.RUN_DISPLAY_URL}"
                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            // create a new application from the template
                            openshift.newApp("${pwd()}/abar.app.yml", "-p", "NAME=${instanceName}")
                        }
                    }
                }
            }
        }

        // Build on a new BuildConfig which also runs tests via spec.postCommit.script
        stage('build') {
            steps {
                githubNotify status: "PENDING", context: "build", description: 'Running build and tests', targetUrl: "${env.RUN_DISPLAY_URL}"
                openshiftBuild(bldCfg: instanceName, commitID: gitCommit, showBuildLogs: 'true')
                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            def builds = openshift.selector("bc", instanceName).related('builds')

                            builds.untilEach(1) {
                                return (it.object().status.phase == "Complete")
                            }
                        }
                    }
                }
                githubNotify status: "SUCCESS", context: "build", description: 'Successful build and tests', targetUrl: "${env.RUN_DISPLAY_URL}"
            }
        }

        // Now that the build (and tests) are successful,
        // we can tag based on branch name if it's not a pull request.
        stage('tag-branch') {
            when {
                allOf {
                    expression { env.CHANGE_ID == null }
                    expression { env.CHANGE_TARGET == null }
                }
            }
            steps {
                openshiftTag(
                  srcStream: instanceName,
                  srcTag: "latest",
                  destStream: "${appName}-${env.BRANCH_NAME}",
                  destTag: gitShortCommit
                )
                openshiftTag(
                  srcStream: "${appName}-${env.BRANCH_NAME}",
                  srcTag: gitShortCommit,
                  destStream: "${appName}-${env.BRANCH_NAME}",
                  destTag: "latest"
                )
            }
        }

        // Deploy a preview instance for this branch
        // pipeline will be paused until a dev "Proceed"s with teardown stage.
        stage('deploy') {
            steps {
                githubNotify status: "SUCCESS", context: "preview", description: 'Deploying preview'
                openshiftScale(depCfg: instanceName, replicaCount: "1")
                openshiftDeploy(depCfg: instanceName)
                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            previewRouteHost = openshift.selector("route", instanceName).object().spec.host
                        }
                    }
                }
                githubNotify status: "SUCCESS", context: "preview", description: 'Preview is online', targetUrl: "http://${previewRouteHost}"
            }
        }
        stage('teardown') {
            steps {
                input message: 'Finished using the web site? (Click "Proceed" to teardown preview instance and tag resulting image)'
                openshiftDeleteResourceByLabels(types: "is,bc,dc,svc,route", keys: "template", values: instanceName)
            }
        }

    }
    post {
        failure {
            deleteEverything(instanceName)
            githubNotify status: "FAILURE", context: "build", targetUrl: "${env.RUN_DISPLAY_URL}", description: "Pipeline failed!"
            githubNotify status: "FAILURE", context: "preview", targetUrl: "${env.RUN_DISPLAY_URL}", description: "Pipeline failed!"
        }
    }
} // pipeline