#What this is

This is an automation-driven approach to the complete lifecycle management of the problem of managing a high-performance, semi-fault tolerant(for a certain value of 'complete') suite of services. It basically tries to minimize the moving pieces involved in first building a test environment in a VPC [which you may want to generate a new IAM user for], the building of deployable containers from well-controlled artifacts, and finally getting those deployed in a monitored/controlled way (for these purposes, load balancer checks over HTTP give us a lot of bang for the buck).

The major technologies in use are SparkleFormation for modeling/orchestration in AWS and Packer for generating repeatable, controlled artifacts for deployment with SparkleFormation/AWS. Good stuff that's saved me a lot of time and headaches.

See the 'docs' folder for more in-detail documentation, and sample logs!

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
``` 

followed by a run of ApacheBench.

Then, you can terminate it when satisfied:
```
bundle exec rake cluster:terminate	  #destroy everything we just made
```

These tasks are, fortunately, more or less stateless to the user- as long as you're operating your cluster from the same git commmits, anyway.

#Room for Improvement

- While the container host allows an arbitrary amount of containers to spin up/down at the request of the application load balancer, the host itself is still a singleton- this means no uninterrupted deployments, unfortunately. Just needs to be put behind an ASG and have additional rules written for its scaling. UPDATE: I've put these behind an ASG so as to make it easier to manually scale these up/down, but right now there is no actual 'auto'scaling on it. The current desired count for real hosts is 2.
- Intermediate artifacts aren't cached independently- like for the build of Ruby and installation of other dependencies for the remote build host used to generate container images. From my connection, generating the build artifacts is the most time-consuming portion at a little over 10 minutes. This could greatly be improved by caching artifacts and probably having a dedicated/pre-baked image for building container images.
- Speaking of, packages should be generated for software especially - like the backend/frontend web services used. Those packages could then be installed directly into our upstream container image (from phusion/baseimage)- removing the intermediate artifacts of a build system. Our containers probably don't need GCC et al- and including it all just adds to the cost of using AWS.
- Security-wise, credentials could be more finely-tuned at least along the services used (see sparkleformation/components/ecs.rb for the IAM role that describes what actions are allowed by which services)
- The CLI doesn't necessarily account for all states that all the dependent services could be in; for a production environment, more care could be put into assuring a certain predictability and ease of debugging.
