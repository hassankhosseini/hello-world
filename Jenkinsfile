appName = "hello-world"

// Function below controls which previews to keep online and not teardown after successful build.
//
// To only teardown PRs previews (and keep all branches previews) use following condition instead:
// env.CHANGE_ID != null
//
// By default we'd always teardown previews except for "master" branch,
// as we assume it is the staging environment.
//
def shouldTeardownPreview() {
    return env.BRANCH_NAME != "master"
}

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
                        buildTarget = "pr${env.CHANGE_ID}"
                    } else {
                        buildTarget = "${env.BRANCH_NAME}".replaceAll(/(\\/|_|-)+/,"-")
                    }

                    instanceName = "${appName}-${buildTarget}"

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
                      imageStreamName = "${appName}-${buildTarget}"
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

        // Deploy a preview instance for this branch/PR (not for tags)
        stage('deploy') {
            when {
                allOf {
                    // Git tags do not need a preview since they must've already had one on their branch
                    expression { env.TAG_NAME == null }
                }
            }
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
                    // Git tags do not need a preview since they must've already had one on their branch
                    expression { env.TAG_NAME == null }
                    expression { shouldTeardownPreview() }
                }
            }
            steps {
                script {
                    echo "Preview is available on: http://${previewRouteHost}"
                    input message: "Finished viewing changes? (Click 'Proceed' to teardown preview instance)"
                }
            }
        }

        // Now that the build (and tests) are successful,
        // We will promote latest imagestream tag. (for git tags only, not branches nor PRs).
        stage('tag') {
            when {
                allOf {
                    expression { env.TAG_NAME != null }
                }
            }
            steps {
                openshiftTag(
                  srcStream: imageStreamName,
                  srcTag: imageStreamTag,
                  destStream: imageStreamName,
                  destTag: env.TAG_NAME
                )
                openshiftTag(
                  srcStream: imageStreamName,
                  srcTag: env.TAG_NAME,
                  destStream: imageStreamName,
                  destTag: "latest"
                )
            }
        }
    }
    post {
        always {
            script {
                if (shouldTeardownPreview()) {
                    deleteEverything(instanceName)
                }
            }
        }
        failure {
            githubNotify status: "FAILURE", context: "build", description: "Pipeline failed!"
            githubNotify status: "FAILURE", context: "preview", description: "Pipeline failed!"
        }
    }
} // pipeline