# Hello World!

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

Follow the instructions [here](https://docs.abarcloud.com).

[This branch](https://github.com/abarcloud/hello_world/tree/advanced) shows some more advanced examples of how to have one repository with multiple starting commands, and how to connect to Memcached or Redis.
