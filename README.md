# Hello World

## To run locally:

```
bundle install
bundle exec rackup
```


## To run locally with Docker:

```
docker build .
docker run -p 8080:8080 MY_IMAGE_ID_FROM_ABOVE
```


## To deploy on AbarCloud:

```
oc new-app https://github.com/abarcloud/hello-world --strategy=docker
```
Follow the instructions [here](https://docs.abarcloud.com) for more info.
