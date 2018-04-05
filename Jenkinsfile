appName = "hello-world"

def deleteEverything(instanceName) {
    openshift.withCluster() {
        openshift.withProject() {
            // Except imagestream
            openshift.selector("replicationcontroller,deployment,build,pod,buildconfig,deploymentconfig,service,route", [app: instanceName]).delete("--ignore-not-found")
        }
    }
}

pipeline {
    options {
        // set a timeout of 30 minutes for this pipeline
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }
    agent {
      node {
        // spin up a slave pod to run this build on
        label 'base'
      }
    }
    stages {
        stage('prepare') {
            steps {
                script {
                    //
                    // Determine (escaped) branch name and instance name
                    //
                    if (env.CHANGE_ID) {
                        targetBranch = "pr${env.CHANGE_ID}"
                    } else {
                        targetBranch = "${env.BRANCH_NAME}".replaceAll("/","-")
                    }

                    instanceName = "${appName}-${targetBranch}"

                    //
                    // Find git commit sha1 useful in various steps
                    //
                    gitCommit = sh(returnStdout: true, script: "git rev-parse HEAD").trim()
                    gitShortCommit = sh(returnStdout: true, script: "git log -n 1 --pretty=format:'%h'").trim()

                    echo ("gitCommit = ${gitCommit}")
                    echo ("gitShortCommit = ${gitShortCommit}")

                    //
                    // Post pending commit statuses to GitHub
                    //
                    githubNotify status: "PENDING", context: "build", description: 'Starting pipeline'
                    githubNotify status: "PENDING", context: "preview", description: 'Waiting for successful build'

                    //
                    // Prepare image streams in OpenShift
                    //
                    if (env.CHANGE_ID) {
                      imageStreamName = "${appName}-pr"
                      imageStreamTag = env.CHANGE_ID
                    } else {
                      imageStreamName = "${appName}-${targetBranch}"
                      imageStreamTag = gitShortCommit
                    }
                    openshift.withCluster() {
                        openshift.withProject() {
                            // Create imagestream if not exist yet
                            if (openshift.selector("imagestream", imageStreamName).count() == 0) {
                                openshift.create([
                                    "kind": "ImageStream",
                                    "metadata": [
                                        "name": "${imageStreamName}"
                                    ]
                                ])
                            }

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
                            openshift.newApp(
                              "${pwd()}/abar.yml",
                              "-p", "NAME=${instanceName}",
                              "-p", "IMAGESTREAM_NAME=${imageStreamName}",
                              "-p", "IMAGESTREAM_TAG=${imageStreamTag}"
                            )

                            // Set a custom env variable on DeploymentConfig
                            openshift.raw("env dc/${instanceName} DEPLOYMENT_ENV=${instanceName}")
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
                githubNotify status: "PENDING", context: "preview", description: 'Deploying preview'

                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            def rm = openshift.selector("dc", instanceName).rollout().latest()

                            openshift.selector("dc", instanceName).related('pods').untilEach(1) {
                                return (it.object().status.phase == "Running")
                            }

                            previewRouteHost = openshift.selector("route", instanceName).object().spec.host
                            echo "Preview is live on: http://${previewRouteHost}"
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
                echo "Preview is available on: http://${previewRouteHost}"
                input message: "Finished viewing changes? (Click "Proceed" to teardown preview instance)'
                deleteEverything(instanceName)
            }
        }

        // Now that the build (and tests) and deployments are successful,
        // We will promote latest tag (for branches).
        stage('tag') {
            when {
                allOf {
                    expression { env.CHANGE_ID == null }
                }
            }
            steps {
                openshiftTag(
                  srcStream: imageStreamName,
                  srcTag: imageStreamTag,
                  destStream: imageStreamName,
                  destTag: "latest"
                )
            }
        }
    }
    post {
        failure {
            githubNotify status: "FAILURE", context: "build", description: "Pipeline failed!"
            githubNotify status: "FAILURE", context: "preview", description: "Pipeline failed!"
        }
    }
} // pipeline