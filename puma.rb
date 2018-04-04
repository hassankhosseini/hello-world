workers Integer(ENV['WEB_CONCURRENCY'] || 1)
threads_count = Integer(ENV['WEB_MAX_THREADS'] || 5)
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 8080
