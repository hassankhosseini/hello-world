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
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
    }
    triggers {
        issueCommentTrigger('.*test this please.*')
    }
    agent any
    stages {
        stage('prepare') {
            steps {
                script {
                    //
                    // Determine build target name, instance name, image stream name and tag
                    //
                    if (env.CHANGE_ID) {
                        buildTarget = "pr-${env.CHANGE_ID}"
                        imageStreamName = "${appName}-contrib"
                        imageStreamTag = "pr-${env.CHANGE_ID}"
                    } else if (env.TAG_NAME) {
                        buildTarget = "release"
                        imageStreamName = "${appName}-release"
                        imageStreamTag = env.TAG_NAME
                    } else if (env.BRANCH_NAME) {
                        buildTarget = "branch-${env.BRANCH_NAME}".replaceAll(/(\\/|_|-)+/,"-")
                        imageStreamName = "${appName}-${buildTarget}"
                        imageStreamTag = "build-${env.BUILD_ID}"
                    } else {
                        error("No branch nor pull-request ID nor git tag was provided")
                    }

                    instanceName = "${appName}-${buildTarget}"

                    //
                    // Post pending commit statuses to GitHub
                    //
                    githubNotify status: "PENDING", context: "build", description: 'Starting pipeline'
                    githubNotify status: "PENDING", context: "preview", description: 'Waiting for successful build', targetUrl: " "

                    //
                    // Find git commit sha1 useful in various steps
                    //
                    gitCommit = sh(returnStdout: true, script: "git rev-parse HEAD").trim()
                    gitShortCommit = sh(returnStdout: true, script: "git log -n 1 --pretty=format:'%h'").trim()
                    gitMessage = sh(returnStdout: true, script: "git log -n 1 --pretty=format:'%B'")

                    // Print variables
                    echo ("buildTarget = ${buildTarget}")
                    echo ("instanceName = ${instanceName}")
                    echo ("imageStreamName = ${imageStreamName}")
                    echo ("imageStreamTag = ${imageStreamTag}")
                    echo ("gitCommit = ${gitCommit}")
                    echo ("gitShortCommit = ${gitShortCommit}")
                    sh("printenv")

                    // Initialize some variables
                    previewResolution = ""
                    needsPreview = gitMessage.contains("[preview]")

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

                            echo "Building, testing and deploying for ${imageStreamName}:${imageStreamTag} in project ${openshift.project()}"
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
                              "-p", "ROUTE_PREFIX=temp-${instanceName}-${gitShortCommit}",
                              "-p", "IMAGESTREAM_NAME=${imageStreamName}",
                              "-p", "IMAGESTREAM_TAG=${imageStreamTag}",
                              "-p", "IMAGESTREAM_NAMESPACE=${openshift.project()}"
                            )

                            // Set a custom env variable on DeploymentConfig
                            openshift.raw("env dc/${instanceName} DEPLOYMENT_ENV=${imageStreamName}:${imageStreamTag}")
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

                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            openshiftBuild(bldCfg: instanceName, commitID: refSpec, showBuildLogs: 'true', waitTime: '30', waitUnit: 'min')

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

        // Deploy a preview instance for this branch/PR/tag
        stage('deploy') {
            when {
                expression { needsPreview }
            }
            steps {
                githubNotify status: "PENDING", context: "preview", description: 'Deploying preview', targetUrl: " "

                script {
                    openshift.withCluster() {
                        openshift.withProject() {
                            def rm = openshift.selector("dc", instanceName).rollout().latest()

                            openshift.selector("dc", instanceName).related('pods').untilEach(1) {
                                return (it.object().status.phase == "Running")
                            }

                            previewRouteHost = openshift.selector("route", instanceName).object().spec.host
                            echo "Preview is live on: http://${previewRouteHost}"

                            if (env.CHANGE_ID) {
                                def found = false
                                def commentBody = "Live preview of build *[${imageStreamName}:${imageStreamTag}](${env.RUN_DISPLAY_URL}) @ ${gitShortCommit}* is available on: http://${previewRouteHost}"
                                for (comment in pullRequest['comments']) {
                                    if (comment['body'].startsWith('Live preview of build')) {
                                        pullRequest.editComment(comment['id'], comment['body'])
                                        found = true
                                        break
                                    }
                                }
                                if (!found) {
                                    pullRequest.comment(commentBody)
                                }
                            }
                        }
                    }
                }

                githubNotify status: "SUCCESS", context: "preview", description: "Preview is online on http://${previewRouteHost}", targetUrl: "http://${previewRouteHost}"
            }
        }
        stage('teardown') {
            when {
                expression { needsPreview }
            }
            steps {
                script {
                    echo "Preview is available on: http://${previewRouteHost}"
                    previewResolution = input message: "Finished viewing changes?",
                            parameters: [choice(name: 'previewResolution', choices: 'Teardown preview instance\nKeep preview online', description: 'Should I destroy the preview instance when this build is finished?')]
                }
            }
        }
    }
    post {
        always {
            script {
                if (previewResolution == "" || previewResolution.contains("Teardown")) {
                    deleteEverything(instanceName)
                }
                if (!needsPreview) {
                    githubNotify status: "SUCCESS", context: "preview", description: "Skipped preview since it was not requested", targetUrl: " "
                }
            }
        }
        success {
            script {
                // Tag successfully built image as latest (except for PRs).
                // This is most useful for myapp-release and myapp-branch-master image streams.
                // For example your staging app can use myapp-branch-master:latest
                if (env.CHANGE_ID == null) {
                    openshiftTag(
                      srcStream: imageStreamName,
                      srcTag: imageStreamTag,
                      destStream: imageStreamName,
                      destTag: "latest"
                    )
                }
            }
        }
        failure {
            script {
                githubNotify status: "FAILURE", context: "build", description: "Pipeline failed!"

                if (!needsPreview) {
                    githubNotify status: "FAILURE", context: "preview", description: "Pipeline failed!", targetUrl: " "
                } else {
                    githubNotify status: "SUCCESS", context: "preview", description: "Skipped preview since it was not requested", targetUrl: " "
                }
            }
        }
    }
} // pipeline