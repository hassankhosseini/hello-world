appName = "hello-world"

def deleteEverything(instanceName) {
    // Except imagestream
    openshiftDeleteResourceByLabels(types: "replicationcontroller,deployment,build,pod,buildconfig,deploymentconfig,service,route", keys: "app", values: instanceName)
}

pipeline {
    options {
        // set a timeout of 25 minutes for this pipeline
        timeout(time: 25, unit: 'MINUTES')
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

                    echo ("gitCommit = ${gitCommit}")
                    echo ("gitShortCommit = ${gitShortCommit}")

                    sh("printenv")

                    githubNotify status: "PENDING", context: "build", description: 'Starting pipeline'
                    githubNotify status: "PENDING", context: "preview", description: 'Waiting for successful build', targetUrl: ""

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
                githubNotify status: "PENDING", context: "build", description: 'Cleaning up old resources'
                deleteEverything(instanceName)
            }
        }

        // Create a new app stack to fully build, deploy and serve this branch
        stage('create') {
            steps {
                githubNotify status: "PENDING", context: "build", description: 'Creating new resources'
                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            // Create imagestream if not exist yet
                            if (openshift.selector("imagestream", instanceName).count() == 0) {
                                openshift.create([
                                    "kind": "ImageStream",
                                    "metadata": [
                                        "name": instanceName,
                                        "labels": [
                                            "app": instanceName,
                                        ]
                                    ]
                                ])
                            }

                            // create a new application from the template
                            openshift.newApp("${pwd()}/abar.yml", "-p", "NAME=${instanceName}")
                        }
                    }
                }
            }
        }

        // Build on a new BuildConfig which also runs tests via spec.postCommit.script
        stage('build') {
            steps {
                githubNotify status: "PENDING", context: "build", description: 'Running build and tests'

                script {
                    if (env.CHANGE_ID) {
                        refSpec = "refs/pull/${env.CHANGE_ID}/head"
                    } else {
                        refSpec = gitCommit
                    }
                }

                echo ("Building based on refSpec = ${refSpec}")

                openshiftBuild(bldCfg: instanceName, commitID: refSpec, showBuildLogs: 'true', waitTime: '30', waitUnit: 'min')
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
                githubNotify status: "SUCCESS", context: "build", description: 'Successful build and tests'
            }
        }

        // Deploy a preview instance for this branch
        // pipeline will be paused until a dev "Proceed"s with teardown stage.
        stage('deploy') {
            steps {
                githubNotify status: "PENDING", context: "preview", description: 'Deploying preview', targetUrl: ""
                openshiftDeploy(depCfg: instanceName)
                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            previewRouteHost = openshift.selector("route", instanceName).object().spec.host
                        }
                    }
                }
                githubNotify status: "SUCCESS", context: "preview", description: "Preview is online on http://${previewRouteHost}", targetUrl: "http://${previewRouteHost}"
            }
        }
        stage('teardown') {
            when {
                allOf {
                    // Do not tear down "master" and "staging" branches
                    expression { env.BRANCH_NAME != "master" }
                    expression { env.BRANCH_NAME != "staging" }
                }
            }
            steps {
                input message: 'Finished using the web site? (Click "Proceed" to teardown preview instance)'
                deleteEverything(instanceName)
            }
        }

        // Now that the build (and tests) and deployments are successful,
        // we can tag based on branch name (if it's not a pull request).
        stage('tag') {
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
    }
    post {
        failure {
            githubNotify status: "FAILURE", context: "build", description: "Pipeline failed!"
            githubNotify status: "FAILURE", context: "preview", description: "Pipeline failed!", targetUrl: ""
        }
    }
} // pipeline