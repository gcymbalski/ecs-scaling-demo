#What this is

This is an automation-driven approach to the complete lifecycle management of the problem of managing a high-performance, semi-fault tolerant(for a certain value of 'complete') suite of services. It basically tries to minimize the moving pieces involved in first building a test environment in a VPC [which you may want to generate a new IAM user for], the building of deployable containers from well-controlled artifacts, and finally getting those deployed in a monitored/controlled way (for these purposes, load balancer checks over HTTP give us a lot of bang for the buck).

The major technologies in use are SparkleFormation for modeling/orchestration in AWS and Packer for generating repeatable, controlled artifacts for deployment with SparkleFormation/AWS. Good stuff that's saved me a lot of time and headaches.

#Major functionality

This shows that some underlying services with a non-ideal failure rate are no reason to not deliver reasonable performance. The major goal is to sustain as many reqs/sec as possible, though there are a ton of ways to do that anywhere, let alone on AWS. For now we'll have a small cluster of managed container hosts that are running a daemon from Amazon that acts as a job scheduler. If our load goes up, boom, we spawn more containers and see if we need to worry about an additional layer of setting up an autoscaling group for Docker/ECS hosts themselves.

#Software Requrements

- Some kind of Unix that lets you have the below tools:
- Git
- Ruby 2.x with Bundler ( `gem install bundler` if you're not sure - and it's probably best if you're using rbenv (whether you compile or use binaries) vs. OS packages, see https://github.com/rbenv/rbenv and https://github.com/rbenv/ruby-build for more)
- Packer for building container images (install from your package manager or https://www.packer.io/downloads.html - fortunately, it's just a binary that needs to be in your $PATH)
- apachebench for testing cluster performance (install from your package manager [apache2-utils on Debian] or `brew install homebrew/apache/ab` if you're on OSX using Homebrew )
Other Reqs
- Have an AWS IAM user set up with admin permissions, with your local environment variables of AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION (n.b. only us-west-2 is supported right now) set appropriately. You'll get yelled at if they aren't filled out. Make sure these match your AWS profile if you've configured the CLI for other stuff, too.

##Caveat to the above
AWS_REGION only supports us-west-2 right now; there are too many moving pieces of information about what is available in which region to reasonably handle more cases than needed. Though this does definitely imply a lack of cross-regional failover.

#Getting Started

With the above out of the way, getting a cluster bootstrapped should hopefully be straightforward. There are basically only five things you can do:

- Initialize a cluster (spinning up the requisite AWS resources we'll need for the rest of bootstrapping)
- Generate container images with the latest binaries built from upstream (built and containerized in one step)
- Deploy those components into the cluster to make it 'live'
- Run benchmarks
- Destroy the cluster and its resources

Best of all, minimal traffic is used on the terminal used to do this. Everything bandwidth-intense happens in AWS.

#Operation of Your Cluster

This is all driven by Rake, a Ruby-driven Make-like framework for simplifying tasks. This being Ruby, we also version control things with Bundler. Long story short, we run 'bundle exec rake' to run 'rake'. Or do what I do and `alias ber='bundle exec rake'`. 

Fortunately, you can start at any of the above steps you want and the right thing will just happen. So, if you want to see the output of ApacheBench, just run the following:

`bundle exec rake test:throughput`

(I like keeping these things in namespaces for clarity)

Completed lifecycle stages:
[x] Build VPC scaffolding (normal VPC 'stuff' + ECS/ECR services)
[x] Build all artifacts
[x] ...On remote host in EC2
[x] Deploy tasks into ECS cluster

This will automatically run the equivalent of the following:
```
bundle exec rake cluster:init	          #build scaffolding
bundle exec rake cluster:remote_artifacts #build artifacts
bundle exec rake cluster:build		  #build out the rest of the services
bundle exec rake cluster:terminate	  #destroy everything we just made
``` 

These tasks are, fortunately, more or less stateless to the user- as long as you're operating your cluster from the same git commmits, anyway.

#Room for Improvement

- For one, while I think this is a decent start to something that could probably be more resiliant if not for all the Amazon in it, it doesn't include the kind of day-to-day tooling that makes a project efficient, like single-keystroke version bumping of artifacts, along with understanding their dependency graph and how to know when to cut and possibly promote a version.
- It also doesn't have automated tests written. For the most part, the pieces are so functionally separated and specialized that I just have to test that the pieces going in don't gum up the works. Speaking of...
- Now that all builds happen in container-capable hosts in EC2 instead relying on Docker locally, there may be even more room for removing non-portable code paths.
